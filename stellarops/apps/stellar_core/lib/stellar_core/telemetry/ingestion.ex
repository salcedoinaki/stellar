defmodule StellarCore.Telemetry.Ingestion do
  @moduledoc """
  Telemetry data ingestion and processing service.

  Handles incoming telemetry from satellites:
  - Validates and normalizes data
  - Persists to database
  - Updates satellite state
  - Triggers alarms on anomalies
  - Broadcasts to subscribers
  """

  use GenServer
  require Logger

  alias StellarCore.Satellite
  alias StellarCore.Alarms
  alias StellarData.Telemetry
  alias Phoenix.PubSub

  @pubsub StellarWeb.PubSub
  @batch_size 100
  @flush_interval_ms 5_000

  # Anomaly thresholds
  @low_energy_warning 20.0
  @low_energy_critical 10.0
  @high_memory_warning 80.0
  @high_memory_critical 95.0
  @temperature_warning 60.0
  @temperature_critical 80.0

  # Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Ingest a telemetry event.

  ## Parameters
    - satellite_id: The satellite that generated the telemetry
    - event_type: Type of telemetry event
    - payload: Event data

  ## Returns
    - :ok - Event queued for processing
  """
  @spec ingest(String.t(), String.t(), map()) :: :ok
  def ingest(satellite_id, event_type, payload) do
    GenServer.cast(__MODULE__, {:ingest, satellite_id, event_type, payload})
  end

  @doc """
  Ingest multiple telemetry events in batch.
  """
  @spec ingest_batch([{String.t(), String.t(), map()}]) :: :ok
  def ingest_batch(events) when is_list(events) do
    GenServer.cast(__MODULE__, {:ingest_batch, events})
  end

  @doc """
  Force flush pending telemetry to database.
  """
  @spec flush() :: :ok
  def flush do
    GenServer.call(__MODULE__, :flush)
  end

  @doc """
  Get ingestion statistics.
  """
  @spec stats() :: map()
  def stats do
    GenServer.call(__MODULE__, :stats)
  end

  # Server Callbacks

  @impl true
  def init(_opts) do
    state = %{
      pending: [],
      stats: %{
        total_ingested: 0,
        total_persisted: 0,
        total_anomalies: 0,
        last_flush: nil
      }
    }

    # Schedule periodic flush
    schedule_flush()

    Logger.info("[TelemetryIngestion] Started")
    {:ok, state}
  end

  @impl true
  def handle_cast({:ingest, satellite_id, event_type, payload}, state) do
    event = build_event(satellite_id, event_type, payload)
    new_pending = [event | state.pending]

    # Process the event for real-time updates
    process_event(event)

    # Check if we need to flush
    new_state =
      if length(new_pending) >= @batch_size do
        flush_pending(%{state | pending: new_pending})
      else
        %{state | pending: new_pending}
      end

    {:noreply, update_stats(new_state, :ingested)}
  end

  @impl true
  def handle_cast({:ingest_batch, events}, state) do
    built_events =
      Enum.map(events, fn {satellite_id, event_type, payload} ->
        build_event(satellite_id, event_type, payload)
      end)

    # Process all events for real-time updates
    Enum.each(built_events, &process_event/1)

    new_pending = built_events ++ state.pending

    new_state =
      if length(new_pending) >= @batch_size do
        flush_pending(%{state | pending: new_pending})
      else
        %{state | pending: new_pending}
      end

    {:noreply, update_stats(new_state, :ingested, length(built_events))}
  end

  @impl true
  def handle_call(:flush, _from, state) do
    new_state = flush_pending(state)
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call(:stats, _from, state) do
    stats = Map.put(state.stats, :pending_count, length(state.pending))
    {:reply, stats, state}
  end

  @impl true
  def handle_info(:flush_timer, state) do
    new_state =
      if length(state.pending) > 0 do
        flush_pending(state)
      else
        state
      end

    schedule_flush()
    {:noreply, new_state}
  end

  # Private Functions

  defp build_event(satellite_id, event_type, payload) do
    %{
      satellite_id: satellite_id,
      event_type: event_type,
      payload: normalize_payload(payload),
      recorded_at: DateTime.utc_now()
    }
  end

  defp normalize_payload(payload) when is_map(payload) do
    payload
    |> Map.new(fn {k, v} -> {to_string(k), v} end)
  end

  defp normalize_payload(payload), do: %{"value" => payload}

  defp process_event(event) do
    # Update satellite state based on telemetry
    update_satellite_state(event)

    # Check for anomalies
    check_anomalies(event)

    # Broadcast to subscribers
    broadcast_telemetry(event)
  end

  defp update_satellite_state(%{satellite_id: sat_id, event_type: type, payload: payload}) do
    case type do
      "energy" ->
        if energy = payload["value"] || payload["energy"] do
          Satellite.update_energy(sat_id, energy)
        end

      "memory" ->
        if memory = payload["value"] || payload["memory_used"] do
          Satellite.update_memory(sat_id, memory)
        end

      "position" ->
        if payload["x"] && payload["y"] && payload["z"] do
          Satellite.update_position(sat_id, {payload["x"], payload["y"], payload["z"]})
        end

      "status" ->
        if mode = payload["mode"] do
          Satellite.set_mode(sat_id, String.to_existing_atom(mode))
        end

      _ ->
        :ok
    end
  end

  defp check_anomalies(%{satellite_id: sat_id, event_type: type, payload: payload}) do
    case type do
      "energy" ->
        energy = payload["value"] || payload["energy"] || 100.0
        check_energy_anomaly(sat_id, energy)

      "memory" ->
        memory = payload["value"] || payload["memory_used"] || 0.0
        check_memory_anomaly(sat_id, memory)

      "temperature" ->
        temp = payload["value"] || payload["temperature"]
        if temp, do: check_temperature_anomaly(sat_id, temp)

      _ ->
        :ok
    end
  end

  defp check_energy_anomaly(satellite_id, energy) when energy <= @low_energy_critical do
    Alarms.low_energy(satellite_id, energy)
  end

  defp check_energy_anomaly(satellite_id, energy) when energy <= @low_energy_warning do
    Alarms.low_energy(satellite_id, energy)
  end

  defp check_energy_anomaly(_, _), do: :ok

  defp check_memory_anomaly(satellite_id, memory) when memory >= @high_memory_critical do
    Alarms.raise_alarm(
      "high_memory",
      :major,
      "Satellite #{satellite_id} memory critical: #{memory}%",
      "satellite:#{satellite_id}",
      %{satellite_id: satellite_id, memory_used: memory}
    )
  end

  defp check_memory_anomaly(satellite_id, memory) when memory >= @high_memory_warning do
    Alarms.raise_alarm(
      "high_memory",
      :warning,
      "Satellite #{satellite_id} memory high: #{memory}%",
      "satellite:#{satellite_id}",
      %{satellite_id: satellite_id, memory_used: memory}
    )
  end

  defp check_memory_anomaly(_, _), do: :ok

  defp check_temperature_anomaly(satellite_id, temp) when temp >= @temperature_critical do
    Alarms.raise_alarm(
      "high_temperature",
      :critical,
      "Satellite #{satellite_id} temperature critical: #{temp}°C",
      "satellite:#{satellite_id}",
      %{satellite_id: satellite_id, temperature: temp}
    )
  end

  defp check_temperature_anomaly(satellite_id, temp) when temp >= @temperature_warning do
    Alarms.raise_alarm(
      "high_temperature",
      :warning,
      "Satellite #{satellite_id} temperature warning: #{temp}°C",
      "satellite:#{satellite_id}",
      %{satellite_id: satellite_id, temperature: temp}
    )
  end

  defp check_temperature_anomaly(_, _), do: :ok

  defp broadcast_telemetry(event) do
    PubSub.broadcast(@pubsub, "telemetry:all", {:telemetry_event, event})
    PubSub.broadcast(@pubsub, "telemetry:#{event.satellite_id}", {:telemetry_event, event})
  end

  defp flush_pending(%{pending: []} = state), do: state

  defp flush_pending(%{pending: pending} = state) do
    # Persist to database
    case Telemetry.create_events_batch(pending) do
      {:ok, count} ->
        Logger.debug("[TelemetryIngestion] Flushed #{count} events")

        %{
          state
          | pending: [],
            stats: %{
              state.stats
              | total_persisted: state.stats.total_persisted + count,
                last_flush: DateTime.utc_now()
            }
        }

      {:error, reason} ->
        Logger.error("[TelemetryIngestion] Flush failed: #{inspect(reason)}")
        # Keep pending for retry
        state
    end
  end

  defp update_stats(state, :ingested, count \\ 1) do
    %{
      state
      | stats: %{state.stats | total_ingested: state.stats.total_ingested + count}
    }
  end

  defp schedule_flush do
    Process.send_after(self(), :flush_timer, @flush_interval_ms)
  end
end
