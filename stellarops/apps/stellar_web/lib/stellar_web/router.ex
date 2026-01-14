defmodule StellarWeb.Router do
  use Phoenix.Router

  import Plug.Conn
  import Phoenix.Controller

  pipeline :api do
    plug :accepts, ["json"]
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
