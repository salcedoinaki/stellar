defmodule StellarWeb.Router do
  use Phoenix.Router

  import Plug.Conn
  import Phoenix.Controller

  alias StellarWeb.Plugs.RateLimiter

  pipeline :api do
    plug :accepts, ["json"]
    plug RateLimiter, limit: 100, window_ms: 60_000, category: "api"
  end

  pipeline :api_strict do
    plug :accepts, ["json"]
    plug RateLimiter, limit: 30, window_ms: 60_000, category: "api_strict"
  end

  scope "/api", StellarWeb do
    pipe_through :api

    # Satellite endpoints
    get "/satellites", SatelliteController, :index
    get "/satellites/:id", SatelliteController, :show
    post "/satellites", SatelliteController, :create
    delete "/satellites/:id", SatelliteController, :delete

    # Satellite state updates
    put "/satellites/:id/energy", SatelliteController, :update_energy
    put "/satellites/:id/mode", SatelliteController, :update_mode
    put "/satellites/:id/memory", SatelliteController, :update_memory

    # Satellite missions (nested)
    get "/satellites/:satellite_id/missions", MissionController, :satellite_missions

    # Mission endpoints (Phase 11)
    get "/missions", MissionController, :index
    get "/missions/stats", MissionController, :stats
    get "/missions/:id", MissionController, :show
    post "/missions", MissionController, :create
    patch "/missions/:id/cancel", MissionController, :cancel
    post "/missions/:id/cancel", MissionController, :cancel
    post "/missions/:id/retry", MissionController, :retry

    # Ground Station endpoints (Phase 11)
    get "/ground_stations", GroundStationController, :index
    get "/ground_stations/bandwidth", GroundStationController, :available_bandwidth
    get "/ground_stations/:id", GroundStationController, :show
    post "/ground_stations", GroundStationController, :create
    patch "/ground_stations/:id", GroundStationController, :update
    delete "/ground_stations/:id", GroundStationController, :delete
    patch "/ground_stations/:id/status", GroundStationController, :set_status
    get "/ground_stations/:id/windows", GroundStationController, :windows

    # Alarm endpoints (Phase 11)
    get "/alarms", AlarmController, :index
    get "/alarms/summary", AlarmController, :summary
    post "/alarms", AlarmController, :create
    get "/alarms/:id", AlarmController, :show
    post "/alarms/:id/acknowledge", AlarmController, :acknowledge
    post "/alarms/:id/resolve", AlarmController, :resolve
    delete "/alarms/resolved", AlarmController, :clear_resolved

    # Command endpoints
    get "/satellites/:satellite_id/commands", CommandController, :index
    get "/satellites/:satellite_id/commands/queue", CommandController, :queue
    get "/satellites/:satellite_id/commands/counts", CommandController, :counts
    post "/satellites/:satellite_id/commands", CommandController, :create
    get "/commands/:id", CommandController, :show
    post "/commands/:id/cancel", CommandController, :cancel

    # Space Objects (SSA catalog)
    get "/space_objects", SpaceObjectController, :index
    get "/space_objects/search", SpaceObjectController, :search
    get "/space_objects/high_threat", SpaceObjectController, :high_threat
    get "/space_objects/protected_assets", SpaceObjectController, :protected_assets
    get "/space_objects/debris", SpaceObjectController, :debris
    get "/space_objects/stale_tle", SpaceObjectController, :stale_tle
    get "/space_objects/counts/by_type", SpaceObjectController, :counts_by_type
    get "/space_objects/counts/by_threat", SpaceObjectController, :counts_by_threat
    get "/space_objects/regime/:regime", SpaceObjectController, :by_regime
    get "/space_objects/near_altitude/:altitude_km", SpaceObjectController, :near_altitude
    get "/space_objects/norad/:norad_id", SpaceObjectController, :show_by_norad
    get "/space_objects/:id", SpaceObjectController, :show
    post "/space_objects", SpaceObjectController, :create
    put "/space_objects/:id", SpaceObjectController, :update
    delete "/space_objects/:id", SpaceObjectController, :delete
    put "/space_objects/:id/threat", SpaceObjectController, :update_threat
    put "/space_objects/:id/tle", SpaceObjectController, :update_tle
    post "/space_objects/:id/link_satellite", SpaceObjectController, :link_to_satellite

    # Conjunction events (SSA threat detection)
    get "/conjunctions", ConjunctionController, :index
    get "/conjunctions/critical", ConjunctionController, :critical
    get "/conjunctions/statistics", ConjunctionController, :statistics
    get "/conjunctions/severity_counts", ConjunctionController, :severity_counts
    get "/conjunctions/detector_status", ConjunctionController, :detector_status
    post "/conjunctions/trigger_screening", ConjunctionController, :trigger_screening
    post "/conjunctions/cleanup", ConjunctionController, :cleanup
    get "/conjunctions/satellite/:satellite_id", ConjunctionController, :for_satellite
    post "/conjunctions/screen_satellite/:satellite_id", ConjunctionController, :screen_satellite
    get "/conjunctions/:id", ConjunctionController, :show
    put "/conjunctions/:id/status", ConjunctionController, :update_status

    # Course of Action (COA) recommendations
    get "/coas", COAController, :index
    get "/coas/pending", COAController, :pending
    get "/coas/urgent", COAController, :urgent
    get "/coas/status_counts", COAController, :status_counts
    get "/coas/planner_status", COAController, :planner_status
    get "/coas/satellite/:satellite_id", COAController, :for_satellite
    get "/coas/conjunction/:conjunction_id", COAController, :for_conjunction
    get "/coas/conjunction/:conjunction_id/recommended", COAController, :recommended
    post "/coas/conjunction/:conjunction_id/generate", COAController, :generate
    post "/coas/conjunction/:conjunction_id/plan_maneuver", COAController, :plan_maneuver
    get "/coas/:id", COAController, :show
    post "/coas/:id/approve", COAController, :approve
    post "/coas/:id/reject", COAController, :reject
  end

  # Health check endpoint
  scope "/", StellarWeb do
    pipe_through :api

    get "/health", HealthController, :index
  end

  # Prometheus metrics endpoint
  scope "/" do
    get "/metrics", PromEx.Plug, prom_ex_module: StellarWeb.PromEx
  end
end
