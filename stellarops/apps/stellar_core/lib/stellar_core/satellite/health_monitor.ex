defmodule StellarCore.Satellite.HealthMonitor do
  @moduledoc """
  Satellite health monitoring service.

  Monitors satellite health through:
  - Heartbeat tracking (communication health)
  - Telemetry analysis (subsystem health)
  - Trend detection (degradation warnings)
  - Automatic mode transitions

  ## Health States
  - :healthy - All systems nominal
  - :degraded - Minor issues, still operational
  - :warning - Issues requiring attention
  - :critical - Major issues, may need intervention
  - :unknown - No recent telemetry

  ## Monitored Subsystems
  - power: Battery, solar panels, power bus
  - thermal: Temperature sensors, heaters
  - attitude: Gyros, magnetometers, reaction wheels
  - communication: Link quality, signal strength
  - payload: Instrument status
  - onboard_computer: Memory, CPU, storage
  """

  use GenServer
  require Logger

  alias StellarCore.Satellite
  alias StellarCore.Alarms
  alias StellarCore.Telemetry.Aggregator
  alias Phoenix.PubSub

  @pubsub StellarWeb.PubSub
  @check_interval 30_000
  @heartbeat_timeout 120_000
  @ets_table :satellite_health

  # Health thresholds per subsystem
  @thresholds %{
    power: %{
      battery_level: %{critical: 10, warning: 20, degraded: 35},
      solar_current: %{critical: 0, warning: 0.1, degraded: 0.5}
    },
    thermal: %{
      temperature: %{critical_low: -40, warning_low: -30, warning_high: 60, critical_high: 70}
    },
    communication: %{
      signal_strength: %{critical: -120, warning: -100, degraded: -80},
      packet_loss: %{critical: 30, warning: 15, degraded: 5}
    },
    onboard_computer: %{
      memory_used: %{critical: 95, warning: 85, degraded: 70},
      cpu_load: %{critical: 95, warning: 80, degraded: 60}
    }
  }

  # ============================================================================
  # Client API
  # ============================================================================

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Get current health status for a satellite.
  """
  def get_health(satellite_id) do
    case :ets.lookup(@ets_table, satellite_id) do
      [{^satellite_id, health}] -> {:ok, health}
      [] -> {:error, :not_found}
    end
  end

  @doc """
  Get health for all monitored satellites.
  """
  def get_all_health do
    :ets.tab2list(@ets_table)
    |> Enum.map(fn {id, health} -> {id, health} end)
    |> Map.new()
  end

  @doc """
  Force a health check for a satellite.
  """
  def check_now(satellite_id) do
    GenServer.cast(__MODULE__, {:check_satellite, satellite_id})
  end

  @doc """
  Record a heartbeat from a satellite.
  """
  def record_heartbeat(satellite_id) do
    GenServer.cast(__MODULE__, {:heartbeat, satellite_id})
  end

  @doc """
  Update health based on new telemetry.
  """
  def update_from_telemetry(satellite_id, telemetry) do
    GenServer.cast(__MODULE__, {:telemetry_update, satellite_id, telemetry})
  end

  # ============================================================================
  # Server Callbacks
  # ============================================================================

  @impl true
  def init(_opts) do
    Logger.info("HealthMonitor starting")

    # Create ETS table
    :ets.new(@ets_table, [:named_table, :set, :public, read_concurrency: true])

    # Schedule periodic checks
    :timer.send_interval(@check_interval, :check_all)

    {:ok, %{}}
  end

  @impl true
  def handle_cast({:heartbeat, satellite_id}, state) do
    update_heartbeat(satellite_id)
    {:noreply, state}
  end

  @impl true
  def handle_cast({:check_satellite, satellite_id}, state) do
    check_satellite_health(satellite_id)
    {:noreply, state}
  end

  @impl true
  def handle_cast({:telemetry_update, satellite_id, telemetry}, state) do
    analyze_telemetry(satellite_id, telemetry)
    {:noreply, state}
  end

  @impl true
  def handle_info(:check_all, state) do
    check_all_satellites()
    {:noreply, state}
  end

  # ============================================================================
  # Private Functions
  # ============================================================================

  defp get_or_init_health(satellite_id) do
    case :ets.lookup(@ets_table, satellite_id) do
      [{^satellite_id, health}] -> health
      [] -> init_health_record(satellite_id)
    end
  end

  defp init_health_record(satellite_id) do
    health = %{
      satellite_id: satellite_id,
      overall_status: :unknown,
      last_heartbeat: nil,
      last_check: nil,
      subsystems: %{
        power: %{status: :unknown, metrics: %{}},
        thermal: %{status: :unknown, metrics: %{}},
        attitude: %{status: :unknown, metrics: %{}},
        communication: %{status: :unknown, metrics: %{}},
        payload: %{status: :unknown, metrics: %{}},
        onboard_computer: %{status: :unknown, metrics: %{}}
      },
      issues: [],
      trends: %{}
    }

    :ets.insert(@ets_table, {satellite_id, health})
    health
  end

  defp update_heartbeat(satellite_id) do
    health = get_or_init_health(satellite_id)
    now = DateTime.utc_now()

    updated = %{health |
      last_heartbeat: now,
      subsystems: Map.update!(health.subsystems, :communication, fn sub ->
        %{sub | status: :healthy}
      end)
    }

    :ets.insert(@ets_table, {satellite_id, updated})
    recalculate_overall_status(satellite_id)
  end

  defp analyze_telemetry(satellite_id, telemetry) do
    health = get_or_init_health(satellite_id)
    now = DateTime.utc_now()

    # Analyze each subsystem
    power_status = analyze_power(telemetry)
    thermal_status = analyze_thermal(telemetry)
    obc_status = analyze_obc(telemetry)

    # Update subsystems
    subsystems = health.subsystems
    |> Map.put(:power, power_status)
    |> Map.put(:thermal, thermal_status)
    |> Map.put(:onboard_computer, obc_status)

    # Collect issues
    issues = collect_issues(subsystems)

    updated = %{health |
      last_heartbeat: now,
      subsystems: subsystems,
      issues: issues
    }

    :ets.insert(@ets_table, {satellite_id, updated})
    
    # Check for alarms
    raise_alarms_if_needed(satellite_id, issues, health.issues)
    
    recalculate_overall_status(satellite_id)
  end

  defp analyze_power(telemetry) do
    battery = Map.get(telemetry, :battery_level) || Map.get(telemetry, :energy_level, 100)
    thresholds = @thresholds.power.battery_level

    status = cond do
      battery <= thresholds.critical -> :critical
      battery <= thresholds.warning -> :warning
      battery <= thresholds.degraded -> :degraded
      true -> :healthy
    end

    %{
      status: status,
      metrics: %{
        battery_level: battery,
        solar_current: Map.get(telemetry, :solar_current)
      }
    }
  end

  defp analyze_thermal(telemetry) do
    temp = Map.get(telemetry, :temperature, 20)
    thresholds = @thresholds.thermal.temperature

    status = cond do
      temp <= thresholds.critical_low or temp >= thresholds.critical_high -> :critical
      temp <= thresholds.warning_low or temp >= thresholds.warning_high -> :warning
      true -> :healthy
    end

    %{
      status: status,
      metrics: %{
        temperature: temp
      }
    }
  end

  defp analyze_obc(telemetry) do
    memory = Map.get(telemetry, :memory_used) || Map.get(telemetry, :storage_used, 0)
    thresholds = @thresholds.onboard_computer.memory_used

    status = cond do
      memory >= thresholds.critical -> :critical
      memory >= thresholds.warning -> :warning
      memory >= thresholds.degraded -> :degraded
      true -> :healthy
    end

    %{
      status: status,
      metrics: %{
        memory_used: memory,
        cpu_load: Map.get(telemetry, :cpu_load)
      }
    }
  end

  defp collect_issues(subsystems) do
    subsystems
    |> Enum.flat_map(fn {subsystem_name, %{status: status, metrics: metrics}} ->
      if status in [:warning, :critical, :degraded] do
        [%{
          subsystem: subsystem_name,
          status: status,
          metrics: metrics,
          detected_at: DateTime.utc_now()
        }]
      else
        []
      end
    end)
  end

  defp raise_alarms_if_needed(satellite_id, new_issues, old_issues) do
    old_subsystems = Enum.map(old_issues, & &1.subsystem) |> MapSet.new()

    Enum.each(new_issues, fn issue ->
      # Only raise alarm for new critical/warning issues
      if issue.status in [:critical, :warning] and not MapSet.member?(old_subsystems, issue.subsystem) do
        severity = if issue.status == :critical, do: :critical, else: :warning

        Alarms.raise_alarm(
          "satellite_health",
          severity,
          "#{issue.subsystem} subsystem #{issue.status}",
          %{
            satellite_id: satellite_id,
            subsystem: issue.subsystem,
            metrics: issue.metrics
          }
        )
      end
    end)
  end

  defp recalculate_overall_status(satellite_id) do
    case :ets.lookup(@ets_table, satellite_id) do
      [{^satellite_id, health}] ->
        # Check heartbeat timeout
        comm_status = check_heartbeat_status(health.last_heartbeat)

        # Get worst subsystem status
        statuses = health.subsystems
        |> Map.values()
        |> Enum.map(& &1.status)
        |> Kernel.++([comm_status])

        overall = calculate_overall(statuses)

        updated = %{health |
          overall_status: overall,
          last_check: DateTime.utc_now()
        }

        :ets.insert(@ets_table, {satellite_id, updated})
        broadcast_health_update(satellite_id, updated)

        # Handle automatic mode transitions
        handle_mode_transition(satellite_id, overall, health.overall_status)

      [] ->
        :ok
    end
  end

  defp check_heartbeat_status(nil), do: :unknown
  defp check_heartbeat_status(last_heartbeat) do
    elapsed = DateTime.diff(DateTime.utc_now(), last_heartbeat, :millisecond)

    cond do
      elapsed > @heartbeat_timeout * 2 -> :critical
      elapsed > @heartbeat_timeout -> :warning
      true -> :healthy
    end
  end

  defp calculate_overall(statuses) do
    cond do
      :critical in statuses -> :critical
      :warning in statuses -> :warning
      :degraded in statuses -> :degraded
      :unknown in statuses and length(Enum.filter(statuses, &(&1 == :unknown))) > 3 -> :unknown
      true -> :healthy
    end
  end

  defp handle_mode_transition(satellite_id, new_status, old_status) do
    # Trigger mode change if status worsens significantly
    case {old_status, new_status} do
      {_, :critical} ->
        Logger.warning("Satellite #{satellite_id} health critical, considering safe mode")
        # Could trigger automatic safe mode here
        # Satellite.transition_mode(satellite_id, :safe)

      {status, :warning} when status in [:healthy, :degraded] ->
        Logger.info("Satellite #{satellite_id} health degraded to warning")

      _ ->
        :ok
    end
  end

  defp check_all_satellites do
    # Get all active satellite processes
    case Satellite.Registry.list_satellites() do
      satellites when is_list(satellites) ->
        Enum.each(satellites, fn {id, _pid} ->
          check_satellite_health(id)
        end)

      _ ->
        :ok
    end
  end

  defp check_satellite_health(satellite_id) do
    health = get_or_init_health(satellite_id)

    # Get aggregated stats for trend analysis
    with {:ok, state} <- Satellite.get_state(satellite_id) do
      analyze_telemetry(satellite_id, state)
    end

    # Check for trends using aggregator
    update_trends(satellite_id, health)
  end

  defp update_trends(satellite_id, health) do
    # Get trends for key metrics
    trends = %{
      battery: get_metric_trend(satellite_id, "battery_level"),
      temperature: get_metric_trend(satellite_id, "temperature"),
      memory: get_metric_trend(satellite_id, "memory_used")
    }

    updated = %{health | trends: trends}
    :ets.insert(@ets_table, {satellite_id, updated})

    # Warn on concerning trends
    Enum.each(trends, fn {metric, trend} ->
      case {metric, trend} do
        {:battery, :decreasing} ->
          Logger.debug("Satellite #{satellite_id}: battery trending down")

        {:temperature, :increasing} ->
          Logger.debug("Satellite #{satellite_id}: temperature trending up")

        {:memory, :increasing} ->
          Logger.debug("Satellite #{satellite_id}: memory usage trending up")

        _ ->
          :ok
      end
    end)
  end

  defp get_metric_trend(satellite_id, metric) do
    case Aggregator.get_trend(satellite_id, metric) do
      {:ok, trend} -> trend
      _ -> :unknown
    end
  rescue
    _ -> :unknown
  end

  defp broadcast_health_update(satellite_id, health) do
    message = %{
      satellite_id: satellite_id,
      overall_status: health.overall_status,
      subsystems: health.subsystems,
      issues: health.issues,
      trends: health.trends,
      last_heartbeat: health.last_heartbeat,
      timestamp: DateTime.utc_now()
    }

    PubSub.broadcast(
      @pubsub,
      "satellite:#{satellite_id}:health",
      {:health_update, message}
    )

    PubSub.broadcast(
      @pubsub,
      "health:updates",
      {:health_update, message}
    )
  end
end
