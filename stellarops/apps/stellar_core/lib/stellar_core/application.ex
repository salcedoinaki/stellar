defmodule StellarCore.Application do
  @moduledoc """
  OTP Application for StellarCore.

  Starts the supervision tree including:
  - Satellite.Registry (for process lookup by ID)
  - Satellite.Supervisor (DynamicSupervisor for managing satellite processes)
  - TaskSupervisor (for mission execution tasks)
  - MissionScheduler (for priority-based mission scheduling)
  - DownlinkManager (for contact window management)
  - Alarms (for alarm and notification tracking)
  """

  use Application

  alias StellarCore.Satellite.Registry
  alias StellarCore.Satellite.Supervisor, as: SatelliteSupervisor
  alias StellarCore.Scheduler.MissionScheduler
  alias StellarCore.Scheduler.DownlinkManager
  alias StellarCore.Alarms

  @impl true
  def start(_type, _args) do
    children = [
      # HTTP client for orbital service with connection pooling
      StellarCore.Orbital.HttpClient,
      # Circuit breaker for orbital service
      StellarCore.Orbital.CircuitBreaker,
      # Cache for orbital service results
      {StellarCore.Orbital.Cache, [ttl: :timer.minutes(5)]},
      # Phase 2: Registry for satellite process lookup
      Registry,
      # Phase 2: DynamicSupervisor for satellite processes
      SatelliteSupervisor,
      # Phase 11: Alarm system
      Alarms,
      # Phase 11: Task supervisor for mission execution
      {Task.Supervisor, name: StellarCore.TaskSupervisor},
      # Phase 11: Mission scheduler (priority queue)
      MissionScheduler,
      # Phase 11: Downlink window manager
      DownlinkManager,
      # Phase 2: Conjunction detector
      StellarCore.ConjunctionDetector
    ]

    opts = [strategy: :one_for_one, name: StellarCore.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
