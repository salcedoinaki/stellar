defmodule StellarCore.Application do
  @moduledoc """
  OTP Application for StellarCore.

  Starts the supervision tree including:
  - Satellite.Registry (for process lookup by ID)
  - Satellite.Supervisor (DynamicSupervisor for managing satellite processes)
  - TaskSupervisor (for mission execution tasks)
  - MissionScheduler (for priority-based mission scheduling)
  - MissionExecutor (for executing missions on satellites)
  - DownlinkManager (for contact window management)
  - Alarms (for alarm and notification tracking)
  - TLE.RefreshService (for periodic TLE updates)
  - Telemetry.Ingestion (for telemetry data processing)
  """

  use Application

  alias StellarCore.Satellite.Registry
  alias StellarCore.Satellite.Supervisor, as: SatelliteSupervisor
  alias StellarCore.Scheduler.MissionScheduler
  alias StellarCore.Scheduler.DownlinkManager
  alias StellarCore.Missions.Executor, as: MissionExecutor
  alias StellarCore.TLE.RefreshService
  alias StellarCore.Telemetry.Ingestion, as: TelemetryIngestion
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
      
      # Mission management
      MissionScheduler,
      MissionExecutor,
      
      # Downlink window manager
      DownlinkManager,
      
      # Telemetry processing
      TelemetryIngestion,
      
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
