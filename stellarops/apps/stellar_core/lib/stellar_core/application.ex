defmodule StellarCore.Application do
  @moduledoc """
  OTP Application for StellarCore.

  Starts the supervision tree including:
  - Satellite.Registry (for process lookup by ID)
  - Satellite.Supervisor (DynamicSupervisor for managing satellite processes)
  - Satellite.HealthMonitor (for health tracking and alerting)
  - TaskSupervisor (for mission execution tasks)
  - MissionScheduler (for priority-based mission scheduling)
  - MissionExecutor (for executing missions on satellites)
  - CommandQueue (for satellite command queueing and dispatch)
  - DownlinkManager (for contact window management)
  - DownlinkScheduler (for scheduling and executing downlinks)
  - Alarms (for alarm and notification tracking)
  - TLE.RefreshService (for periodic TLE updates)
  - Telemetry.Ingestion (for telemetry data processing)
  - Telemetry.Aggregator (for telemetry statistics and trends)
  """

  use Application

  alias StellarCore.Satellite.Registry
  alias StellarCore.Satellite.Supervisor, as: SatelliteSupervisor
  alias StellarCore.Satellite.HealthMonitor
  alias StellarCore.Scheduler.MissionScheduler
  alias StellarCore.Scheduler.DownlinkManager
  alias StellarCore.Scheduler.DownlinkScheduler
  alias StellarCore.Missions.Executor, as: MissionExecutor
  alias StellarCore.Commands.CommandQueue
  alias StellarCore.TLE.RefreshService
  alias StellarCore.Telemetry.Ingestion, as: TelemetryIngestion
  alias StellarCore.Telemetry.Aggregator, as: TelemetryAggregator
  alias StellarCore.Alarms

  @impl true
  def start(_type, _args) do
    children = [
      # Core infrastructure
      Registry,
      SatelliteSupervisor,
      
      # Task supervisor for background work
      {Task.Supervisor, name: StellarCore.TaskSupervisor},
      
      # Alarm system
      Alarms,
      
      # Satellite health monitoring
      HealthMonitor,
      
      # Mission management
      MissionScheduler,
      MissionExecutor,
      
      # Command queue
      CommandQueue,
      
      # Downlink management
      DownlinkManager,
      DownlinkScheduler,
      
      # Telemetry processing
      TelemetryIngestion,
      TelemetryAggregator,
      
      # TLE refresh (optional, can be disabled via config)
      {RefreshService, enabled: tle_refresh_enabled?()}
    ]

    opts = [strategy: :one_for_one, name: StellarCore.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp tle_refresh_enabled? do
    Application.get_env(:stellar_core, RefreshService, [])
    |> Keyword.get(:enabled, true)
  end
end
