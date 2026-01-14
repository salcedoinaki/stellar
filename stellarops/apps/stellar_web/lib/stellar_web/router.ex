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
  end

  # Health check endpoint
  scope "/", StellarWeb do
    pipe_through :api

    get "/health", HealthController, :index
  end
end
