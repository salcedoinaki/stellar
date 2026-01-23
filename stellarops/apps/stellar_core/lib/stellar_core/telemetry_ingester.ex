defmodule StellarCore.TelemetryIngester do
  @moduledoc """
  Ingests telemetry data from satellites and ground systems.
  
  Provides:
  - HTTP and message queue telemetry receivers
  - Data validation and parsing
  - Anomaly detection
  - Satellite state updates
  - Data retention policy enforcement
  """
  
  use GenServer
  require Logger
  
  alias StellarData.Telemetry
  alias StellarCore.Satellite
  alias StellarCore.Alarms
  
  @retention_days 90
  @anomaly_thresholds %{
    energy_low: 15.0,
    energy_critical: 5.0,
    memory_high: 90.0,
    memory_critical: 95.0,
    temperature_high: 60.0,
    temperature_critical: 80.0,
    temperature_low: -40.0
  }
  
  # ============================================================================
  # Client API
  # ============================================================================
  
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @doc """
  Ingest a single telemetry event.
  
  ## Parameters
  - satellite_id: The satellite that generated the telemetry
  - event_type: Type of telemetry event (e.g., "status", "position", "health")
  - payload: Event data as a map
  - opts: Additional options
    - :recorded_at - When the telemetry was recorded (defaults to now)
    - :source - Source of telemetry (e.g., "ground_station", "direct_link")
  """
  def ingest(satellite_id, event_type, payload, opts \\ []) do
    GenServer.call(__MODULE__, {:ingest, satellite_id, event_type, payload, opts})
  end
  
  @doc """
  Ingest a batch of telemetry events.
  """
  def ingest_batch(events) when is_list(events) do
    GenServer.call(__MODULE__, {:ingest_batch, events}, :timer.seconds(30))
  end
  
  @doc """
  Get ingestion statistics.
  """
  def stats do
    GenServer.call(__MODULE__, :stats)
  end
  
  @doc """
  Trigger retention policy cleanup.
  """
  def cleanup_old_telemetry do
    GenServer.call(__MODULE__, :cleanup, :timer.minutes(5))
  end
  
  @doc """
  Get anomaly detection thresholds.
  """
  def thresholds do
    @anomaly_thresholds
  end
  
  # ============================================================================
  # GenServer Callbacks
  # ============================================================================
  
  @impl true
  def init(opts) do
    retention_days = Keyword.get(opts, :retention_days, @retention_days)
    
    state = %{
      retention_days: retention_days,
      ingested_count: 0,
      anomaly_count: 0,
      error_count: 0,
      last_ingestion: nil,
      anomaly_thresholds: @anomaly_thresholds
    }
    
    # Schedule periodic cleanup
    Process.send_after(self(), :scheduled_cleanup, :timer.hours(24))
    
    Logger.info("TelemetryIngester started with #{retention_days} day retention")
    {:ok, state}
  end
  
  @impl true
  def handle_call({:ingest, satellite_id, event_type, payload, opts}, _from, state) do
    case do_ingest(satellite_id, event_type, payload, opts, state) do
      {:ok, event, anomalies} ->
        new_state = %{state | 
          ingested_count: state.ingested_count + 1,
          anomaly_count: state.anomaly_count + length(anomalies),
          last_ingestion: DateTime.utc_now()
        }
        {:reply, {:ok, event, anomalies}, new_state}
        
      {:error, reason} = error ->
        new_state = %{state | error_count: state.error_count + 1}
        {:reply, error, new_state}
    end
  end
  
  @impl true
  def handle_call({:ingest_batch, events}, _from, state) do
    results = Enum.map(events, fn event ->
      do_ingest(
        event.satellite_id,
        event.event_type,
        event.payload,
        Map.get(event, :opts, []),
        state
      )
    end)
    
    successes = Enum.count(results, &match?({:ok, _, _}, &1))
    errors = Enum.count(results, &match?({:error, _}, &1))
    anomalies = results
                |> Enum.filter(&match?({:ok, _, _}, &1))
                |> Enum.map(fn {:ok, _, a} -> length(a) end)
                |> Enum.sum()
    
    new_state = %{state | 
      ingested_count: state.ingested_count + successes,
      error_count: state.error_count + errors,
      anomaly_count: state.anomaly_count + anomalies,
      last_ingestion: DateTime.utc_now()
    }
    
    {:reply, {:ok, %{ingested: successes, errors: errors, anomalies: anomalies}}, new_state}
  end
  
  @impl true
  def handle_call(:stats, _from, state) do
    stats = %{
      ingested_count: state.ingested_count,
      anomaly_count: state.anomaly_count,
      error_count: state.error_count,
      last_ingestion: state.last_ingestion,
      retention_days: state.retention_days
    }
    {:reply, stats, state}
  end
  
  @impl true
  def handle_call(:cleanup, _from, state) do
    result = do_cleanup(state.retention_days)
    {:reply, result, state}
  end
  
  @impl true
  def handle_info(:scheduled_cleanup, state) do
    Logger.info("Running scheduled telemetry cleanup")
    do_cleanup(state.retention_days)
    Process.send_after(self(), :scheduled_cleanup, :timer.hours(24))
    {:noreply, state}
  end
  
  # ============================================================================
  # Private Functions - Ingestion
  # ============================================================================
  
  defp do_ingest(satellite_id, event_type, payload, opts, state) do
    recorded_at = Keyword.get(opts, :recorded_at, DateTime.utc_now())
    source = Keyword.get(opts, :source, "unknown")
    
    with :ok <- validate_telemetry(satellite_id, event_type, payload),
         {:ok, normalized} <- normalize_payload(event_type, payload),
         {:ok, event} <- store_telemetry(satellite_id, event_type, normalized, recorded_at, source),
         :ok <- update_satellite_state(satellite_id, event_type, normalized),
         anomalies <- detect_anomalies(satellite_id, event_type, normalized, state.anomaly_thresholds) do
      
      # Emit telemetry metrics
      :telemetry.execute(
        [:stellar, :telemetry_ingester, :event],
        %{count: 1},
        %{satellite_id: satellite_id, event_type: event_type, source: source}
      )
      
      # Handle any detected anomalies
      handle_anomalies(satellite_id, anomalies)
      
      {:ok, event, anomalies}
    end
  end
  
  defp validate_telemetry(satellite_id, event_type, payload) do
    cond do
      is_nil(satellite_id) or satellite_id == "" ->
        {:error, :missing_satellite_id}
        
      is_nil(event_type) or event_type == "" ->
        {:error, :missing_event_type}
        
      not is_map(payload) ->
        {:error, :invalid_payload_format}
        
      true ->
        :ok
    end
  end
  
  defp normalize_payload("status", payload) do
    normalized = %{
      energy: normalize_number(Map.get(payload, "energy") || Map.get(payload, :energy)),
      memory: normalize_number(Map.get(payload, "memory") || Map.get(payload, :memory)),
      mode: normalize_mode(Map.get(payload, "mode") || Map.get(payload, :mode)),
      temperature: normalize_number(Map.get(payload, "temperature") || Map.get(payload, :temperature))
    }
    |> Enum.reject(fn {_, v} -> is_nil(v) end)
    |> Map.new()
    
    {:ok, normalized}
  end
  
  defp normalize_payload("position", payload) do
    normalized = %{
      latitude: normalize_number(Map.get(payload, "latitude") || Map.get(payload, :latitude)),
      longitude: normalize_number(Map.get(payload, "longitude") || Map.get(payload, :longitude)),
      altitude: normalize_number(Map.get(payload, "altitude") || Map.get(payload, :altitude)),
      velocity: normalize_number(Map.get(payload, "velocity") || Map.get(payload, :velocity))
    }
    |> Enum.reject(fn {_, v} -> is_nil(v) end)
    |> Map.new()
    
    {:ok, normalized}
  end
  
  defp normalize_payload("health", payload) do
    {:ok, payload}
  end
  
  defp normalize_payload(_event_type, payload) do
    {:ok, payload}
  end
  
  defp normalize_number(nil), do: nil
  defp normalize_number(n) when is_number(n), do: n
  defp normalize_number(s) when is_binary(s) do
    case Float.parse(s) do
      {n, _} -> n
      :error -> nil
    end
  end
  defp normalize_number(_), do: nil
  
  defp normalize_mode(nil), do: nil
  defp normalize_mode(m) when is_atom(m), do: m
  defp normalize_mode(m) when is_binary(m) do
    case String.downcase(m) do
      "nominal" -> :nominal
      "safe" -> :safe
      "critical" -> :critical
      "standby" -> :standby
      _ -> nil
    end
  end
  
  defp store_telemetry(satellite_id, event_type, payload, recorded_at, source) do
    attrs = %{
      satellite_id: satellite_id,
      event_type: event_type,
      payload: Map.put(payload, :source, source),
      recorded_at: recorded_at
    }
    
    Telemetry.create_event(attrs)
  end
  
  defp update_satellite_state(satellite_id, "status", payload) do
    updates = []
    
    updates = if energy = Map.get(payload, :energy) do
      [{:energy, energy} | updates]
    else
      updates
    end
    
    updates = if memory = Map.get(payload, :memory) do
      [{:memory, memory} | updates]
    else
      updates
    end
    
    updates = if mode = Map.get(payload, :mode) do
      [{:mode, mode} | updates]
    else
      updates
    end
    
    if updates != [] do
      case Satellite.get(satellite_id) do
        {:ok, _state} ->
          Enum.each(updates, fn
            {:energy, e} -> Satellite.update_energy(satellite_id, e - 50)  # Delta from 50%
            {:memory, m} -> Satellite.update_memory(satellite_id, m - 50)
            {:mode, m} -> Satellite.set_mode(satellite_id, m)
          end)
          :ok
          
        {:error, :not_found} ->
          :ok  # Satellite not running, skip state update
      end
    else
      :ok
    end
  end
  
  defp update_satellite_state(satellite_id, "position", payload) do
    lat = Map.get(payload, :latitude)
    lon = Map.get(payload, :longitude)
    alt = Map.get(payload, :altitude)
    
    if lat && lon && alt do
      case Satellite.get(satellite_id) do
        {:ok, _state} ->
          Satellite.update_position(satellite_id, lat, lon, alt)
          :ok
          
        {:error, :not_found} ->
          :ok
      end
    else
      :ok
    end
  end
  
  defp update_satellite_state(_satellite_id, _event_type, _payload), do: :ok
  
  # ============================================================================
  # Private Functions - Anomaly Detection
  # ============================================================================
  
  defp detect_anomalies(satellite_id, "status", payload, thresholds) do
    anomalies = []
    
    # Check energy
    anomalies = case Map.get(payload, :energy) do
      nil -> anomalies
      e when e <= thresholds.energy_critical ->
        [{:critical_energy, "Energy at critical level: #{e}%", :critical} | anomalies]
      e when e <= thresholds.energy_low ->
        [{:low_energy, "Energy below threshold: #{e}%", :warning} | anomalies]
      _ -> anomalies
    end
    
    # Check memory
    anomalies = case Map.get(payload, :memory) do
      nil -> anomalies
      m when m >= thresholds.memory_critical ->
        [{:critical_memory, "Memory at critical level: #{m}%", :critical} | anomalies]
      m when m >= thresholds.memory_high ->
        [{:high_memory, "Memory above threshold: #{m}%", :warning} | anomalies]
      _ -> anomalies
    end
    
    # Check temperature
    anomalies = case Map.get(payload, :temperature) do
      nil -> anomalies
      t when t >= thresholds.temperature_critical ->
        [{:critical_temp_high, "Temperature critical: #{t}°C", :critical} | anomalies]
      t when t >= thresholds.temperature_high ->
        [{:high_temp, "Temperature above threshold: #{t}°C", :warning} | anomalies]
      t when t <= thresholds.temperature_low ->
        [{:low_temp, "Temperature below threshold: #{t}°C", :warning} | anomalies]
      _ -> anomalies
    end
    
    anomalies
  end
  
  defp detect_anomalies(_satellite_id, _event_type, _payload, _thresholds), do: []
  
  defp handle_anomalies(_satellite_id, []), do: :ok
  
  defp handle_anomalies(satellite_id, anomalies) do
    Enum.each(anomalies, fn {type, message, severity} ->
      alarm_severity = case severity do
        :critical -> :critical
        :warning -> :warning
        _ -> :minor
      end
      
      Alarms.raise_alarm(
        type,
        message,
        alarm_severity,
        "satellite:#{satellite_id}",
        %{satellite_id: satellite_id, anomaly_type: type}
      )
      
      Logger.warning("Anomaly detected for #{satellite_id}: #{message}")
    end)
  end
  
  # ============================================================================
  # Private Functions - Retention
  # ============================================================================
  
  defp do_cleanup(retention_days) do
    cutoff = DateTime.utc_now() |> DateTime.add(-retention_days, :day)
    
    Logger.info("Cleaning up telemetry older than #{retention_days} days (before #{cutoff})")
    
    case Telemetry.delete_events_before(cutoff) do
      {:ok, count} ->
        Logger.info("Deleted #{count} old telemetry events")
        
        :telemetry.execute(
          [:stellar, :telemetry_ingester, :cleanup],
          %{deleted: count},
          %{retention_days: retention_days}
        )
        
        {:ok, count}
        
      {:error, reason} = error ->
        Logger.error("Telemetry cleanup failed: #{inspect(reason)}")
        error
    end
  end
end
