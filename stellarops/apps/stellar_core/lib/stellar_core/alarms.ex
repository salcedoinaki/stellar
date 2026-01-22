defmodule StellarCore.Alarms do
  @moduledoc """
  Alarm and notification system for StellarOps.

  Provides:
  - In-memory alarm tracking with severity levels (ETS for fast access)
  - Database persistence via StellarData.Alarms
  - PubSub broadcasting for real-time notifications
  - Automatic alarm generation from mission failures
  - Alarm acknowledgment and resolution
  """

  use GenServer
  require Logger

  alias Phoenix.PubSub
  alias StellarData.Alarms, as: AlarmsDB

  @pubsub StellarWeb.PubSub

  @type severity :: :critical | :major | :minor | :warning | :info
  @type alarm_status :: :active | :acknowledged | :resolved

  @type alarm :: %{
          id: String.t(),
          type: String.t(),
          severity: severity(),
          message: String.t(),
          source: String.t(),
          details: map(),
          status: alarm_status(),
          created_at: DateTime.t(),
          acknowledged_at: DateTime.t() | nil,
          resolved_at: DateTime.t() | nil,
          acknowledged_by: String.t() | nil
        }

  # Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Raises a new alarm.
  """
  @spec raise_alarm(String.t(), severity(), String.t(), String.t(), map()) :: {:ok, alarm()}
  def raise_alarm(type, severity, message, source, details \\ %{}) do
    GenServer.call(__MODULE__, {:raise_alarm, type, severity, message, source, details})
  end

  @doc """
  Convenience function to raise a mission failure alarm.
  """
  @spec mission_failed(String.t(), String.t(), String.t(), integer()) :: {:ok, alarm()}
  def mission_failed(mission_id, mission_name, error, retry_count) do
    severity = if retry_count >= 3, do: :major, else: :warning

    raise_alarm(
      "mission_failure",
      severity,
      "Mission '#{mission_name}' failed: #{error}",
      "mission:#{mission_id}",
      %{
        mission_id: mission_id,
        mission_name: mission_name,
        error: error,
        retry_count: retry_count
      }
    )
  end

  @doc """
  Raises a critical alarm when a mission has exhausted all retries.
  """
  @spec mission_permanently_failed(String.t(), String.t(), String.t()) :: {:ok, alarm()}
  def mission_permanently_failed(mission_id, mission_name, error) do
    raise_alarm(
      "mission_permanent_failure",
      :critical,
      "Mission '#{mission_name}' permanently failed after max retries: #{error}",
      "mission:#{mission_id}",
      %{
        mission_id: mission_id,
        mission_name: mission_name,
        error: error
      }
    )
  end

  @doc """
  Raises an alarm when a satellite becomes unhealthy.
  """
  @spec satellite_unhealthy(String.t(), String.t()) :: {:ok, alarm()}
  def satellite_unhealthy(satellite_id, reason) do
    raise_alarm(
      "satellite_unhealthy",
      :major,
      "Satellite #{satellite_id} is unhealthy: #{reason}",
      "satellite:#{satellite_id}",
      %{satellite_id: satellite_id, reason: reason}
    )
  end

  @doc """
  Raises an alarm for low satellite energy.
  """
  @spec low_energy(String.t(), float()) :: {:ok, alarm()}
  def low_energy(satellite_id, energy_level) do
    severity = if energy_level < 10.0, do: :major, else: :warning

    raise_alarm(
      "low_energy",
      severity,
      "Satellite #{satellite_id} has low energy: #{energy_level}%",
      "satellite:#{satellite_id}",
      %{satellite_id: satellite_id, energy_level: energy_level}
    )
  end

  @doc """
  Raises an alarm for ground station connectivity issues.
  """
  @spec ground_station_offline(String.t(), String.t()) :: {:ok, alarm()}
  def ground_station_offline(station_id, station_name) do
    raise_alarm(
      "ground_station_offline",
      :major,
      "Ground station '#{station_name}' is offline",
      "ground_station:#{station_id}",
      %{station_id: station_id, station_name: station_name}
    )
  end

  @doc """
  Acknowledges an alarm.
  """
  @spec acknowledge(String.t(), String.t()) :: :ok | {:error, :not_found}
  def acknowledge(alarm_id, user \\ "system") do
    GenServer.call(__MODULE__, {:acknowledge, alarm_id, user})
  end

  @doc """
  Resolves an alarm.
  """
  @spec resolve(String.t()) :: :ok | {:error, :not_found}
  def resolve(alarm_id) do
    GenServer.call(__MODULE__, {:resolve, alarm_id})
  end

  @doc """
  Lists all alarms, optionally filtered by status.
  """
  @spec list_alarms(keyword()) :: [alarm()]
  def list_alarms(opts \\ []) do
    GenServer.call(__MODULE__, {:list_alarms, opts})
  end

  @doc """
  Gets a specific alarm by ID.
  """
  @spec get_alarm(String.t()) :: {:ok, alarm()} | {:error, :not_found}
  def get_alarm(alarm_id) do
    GenServer.call(__MODULE__, {:get_alarm, alarm_id})
  end

  @doc """
  Gets counts by severity and status.
  """
  @spec get_summary() :: map()
  def get_summary do
    GenServer.call(__MODULE__, :get_summary)
  end

  @doc """
  Clears resolved alarms older than the given duration.
  """
  @spec clear_resolved(integer()) :: {:ok, integer()}
  def clear_resolved(older_than_seconds \\ 86400) do
    GenServer.call(__MODULE__, {:clear_resolved, older_than_seconds})
  end

  # Server Callbacks

  @impl true
  def init(_opts) do
    # ETS table for fast alarm lookups
    :ets.new(:stellar_alarms, [:named_table, :set, :public, read_concurrency: true])

    # Load active alarms from database on startup
    spawn_link(fn -> load_alarms_from_db() end)

    Logger.info("[Alarms] Alarm system started")
    {:ok, %{}}
  end

  defp load_alarms_from_db do
    # Small delay to ensure DB is available
    Process.sleep(1000)

    try do
      alarms = AlarmsDB.list_alarms(status: :active)

      Enum.each(alarms, fn db_alarm ->
        alarm = db_alarm_to_map(db_alarm)
        :ets.insert(:stellar_alarms, {alarm.id, alarm})
      end)

      Logger.info("[Alarms] Loaded #{length(alarms)} active alarms from database")
    rescue
      error ->
        Logger.warning("[Alarms] Failed to load alarms from database: #{inspect(error)}")
    end
  end

  defp db_alarm_to_map(db_alarm) do
    %{
      id: db_alarm.id,
      type: db_alarm.type,
      severity: db_alarm.severity,
      message: db_alarm.message,
      source: db_alarm.source,
      details: db_alarm.details || %{},
      status: db_alarm.status,
      created_at: db_alarm.inserted_at,
      acknowledged_at: db_alarm.acknowledged_at,
      resolved_at: db_alarm.resolved_at,
      acknowledged_by: db_alarm.acknowledged_by
    }
  end

  @impl true
  def handle_call({:raise_alarm, type, severity, message, source, details}, _from, state) do
    # Extract satellite_id from source if present (format: "satellite:SAT-001")
    satellite_id = extract_satellite_id(source)

    # Persist to database first
    db_attrs = %{
      type: type,
      severity: severity,
      message: message,
      source: source,
      details: details,
      satellite_id: satellite_id
    }

    {alarm_id, created_at} =
      case AlarmsDB.create_alarm(db_attrs) do
        {:ok, db_alarm} ->
          {db_alarm.id, db_alarm.inserted_at}

        {:error, _changeset} ->
          # Fallback to generated ID if DB fails
          Logger.warning("[Alarms] Failed to persist alarm to database, using in-memory only")
          {generate_alarm_id(), DateTime.utc_now()}
      end

    alarm = %{
      id: alarm_id,
      type: type,
      severity: severity,
      message: message,
      source: source,
      details: details,
      status: :active,
      created_at: created_at,
      acknowledged_at: nil,
      resolved_at: nil,
      acknowledged_by: nil
    }

    :ets.insert(:stellar_alarms, {alarm.id, alarm})

    # Log based on severity
    log_alarm(alarm)

    # Broadcast to subscribers
    broadcast_alarm(:alarm_raised, alarm)

    {:reply, {:ok, alarm}, state}
  end

  defp extract_satellite_id(source) do
    case String.split(source, ":") do
      ["satellite", sat_id] -> sat_id
      _ -> nil
    end
  end

  @impl true
  def handle_call({:acknowledge, alarm_id, user}, _from, state) do
    case :ets.lookup(:stellar_alarms, alarm_id) do
      [{^alarm_id, alarm}] ->
        updated = %{
          alarm
          | status: :acknowledged,
            acknowledged_at: DateTime.utc_now(),
            acknowledged_by: user
        }

        :ets.insert(:stellar_alarms, {alarm_id, updated})

        # Persist to database
        AlarmsDB.acknowledge_alarm(alarm_id, user)

        broadcast_alarm(:alarm_acknowledged, updated)
        {:reply, :ok, state}

      [] ->
        {:reply, {:error, :not_found}, state}
    end
  end

  @impl true
  def handle_call({:resolve, alarm_id}, _from, state) do
    case :ets.lookup(:stellar_alarms, alarm_id) do
      [{^alarm_id, alarm}] ->
        updated = %{alarm | status: :resolved, resolved_at: DateTime.utc_now()}
        :ets.insert(:stellar_alarms, {alarm_id, updated})

        # Persist to database
        AlarmsDB.resolve_alarm(alarm_id)

        broadcast_alarm(:alarm_resolved, updated)
        {:reply, :ok, state}

      [] ->
        {:reply, {:error, :not_found}, state}
    end
  end

  @impl true
  def handle_call({:list_alarms, opts}, _from, state) do
    status = Keyword.get(opts, :status)
    severity = Keyword.get(opts, :severity)
    source = Keyword.get(opts, :source)
    limit = Keyword.get(opts, :limit, 100)

    alarms =
      :ets.tab2list(:stellar_alarms)
      |> Enum.map(fn {_id, alarm} -> alarm end)
      |> filter_by_status(status)
      |> filter_by_severity(severity)
      |> filter_by_source(source)
      |> Enum.sort_by(& &1.created_at, {:desc, DateTime})
      |> Enum.take(limit)

    {:reply, alarms, state}
  end

  @impl true
  def handle_call({:get_alarm, alarm_id}, _from, state) do
    case :ets.lookup(:stellar_alarms, alarm_id) do
      [{^alarm_id, alarm}] -> {:reply, {:ok, alarm}, state}
      [] -> {:reply, {:error, :not_found}, state}
    end
  end

  @impl true
  def handle_call(:get_summary, _from, state) do
    alarms =
      :ets.tab2list(:stellar_alarms)
      |> Enum.map(fn {_id, alarm} -> alarm end)

    summary = %{
      total: length(alarms),
      by_status: Enum.frequencies_by(alarms, & &1.status),
      by_severity: Enum.frequencies_by(alarms, & &1.severity),
      active_critical: Enum.count(alarms, &(&1.status == :active and &1.severity == :critical)),
      active_major: Enum.count(alarms, &(&1.status == :active and &1.severity == :major))
    }

    {:reply, summary, state}
  end

  @impl true
  def handle_call({:clear_resolved, older_than_seconds}, _from, state) do
    cutoff = DateTime.add(DateTime.utc_now(), -older_than_seconds, :second)

    to_delete =
      :ets.tab2list(:stellar_alarms)
      |> Enum.filter(fn {_id, alarm} ->
        alarm.status == :resolved and
          alarm.resolved_at != nil and
          DateTime.compare(alarm.resolved_at, cutoff) == :lt
      end)
      |> Enum.map(fn {id, _alarm} -> id end)

    Enum.each(to_delete, &:ets.delete(:stellar_alarms, &1))

    # Also clear from database
    {db_deleted, _} = AlarmsDB.clear_resolved(older_than_seconds)
    Logger.info("[Alarms] Cleared #{length(to_delete)} from ETS, #{db_deleted} from database")

    {:reply, {:ok, length(to_delete)}, state}
  end

  # Private helpers

  defp generate_alarm_id do
    "alarm_" <>
      (DateTime.utc_now() |> DateTime.to_unix(:millisecond) |> Integer.to_string()) <>
      "_" <> (:crypto.strong_rand_bytes(4) |> Base.encode16(case: :lower))
  end

  defp log_alarm(alarm) do
    case alarm.severity do
      :critical ->
        Logger.error("[ALARM:CRITICAL] #{alarm.message}",
          alarm_id: alarm.id,
          alarm_type: alarm.type,
          source: alarm.source
        )

      :major ->
        Logger.warning("[ALARM:MAJOR] #{alarm.message}",
          alarm_id: alarm.id,
          alarm_type: alarm.type,
          source: alarm.source
        )

      :minor ->
        Logger.warning("[ALARM:MINOR] #{alarm.message}",
          alarm_id: alarm.id,
          alarm_type: alarm.type,
          source: alarm.source
        )

      :warning ->
        Logger.info("[ALARM:WARNING] #{alarm.message}",
          alarm_id: alarm.id,
          alarm_type: alarm.type,
          source: alarm.source
        )

      :info ->
        Logger.info("[ALARM:INFO] #{alarm.message}",
          alarm_id: alarm.id,
          alarm_type: alarm.type,
          source: alarm.source
        )
    end
  end

  defp broadcast_alarm(event, alarm) do
    PubSub.broadcast(@pubsub, "alarms:all", {event, alarm})
    PubSub.broadcast(@pubsub, "alarms:#{alarm.source}", {event, alarm})
  end

  defp filter_by_status(alarms, nil), do: alarms
  defp filter_by_status(alarms, status), do: Enum.filter(alarms, &(&1.status == status))

  defp filter_by_severity(alarms, nil), do: alarms
  defp filter_by_severity(alarms, severity), do: Enum.filter(alarms, &(&1.severity == severity))

  defp filter_by_source(alarms, nil), do: alarms

  defp filter_by_source(alarms, source) do
    Enum.filter(alarms, &String.starts_with?(&1.source, source))
  end
end
