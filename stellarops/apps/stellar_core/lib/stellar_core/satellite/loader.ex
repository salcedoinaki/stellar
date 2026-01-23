defmodule StellarCore.Satellite.Loader do
  @moduledoc """
  Loads satellites from the database on application startup.
  
  Starts a GenServer process for each satellite stored in the database,
  ensuring they appear in the runtime satellite registry and API.
  """
  
  use GenServer
  require Logger
  
  alias StellarCore.Satellite.Supervisor, as: SatelliteSupervisor
  
  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end
  
  @impl true
  def init(_) do
    # Load satellites after a short delay to ensure DB is ready
    {:ok, %{}, {:continue, :load_satellites}}
  end
  
  @impl true
  def handle_continue(:load_satellites, state) do
    load_satellites_from_database()
    {:noreply, state}
  end
  
  defp load_satellites_from_database do
    Logger.info("[SatelliteLoader] Loading satellites from database...")
    
    try do
      satellites = StellarData.Satellites.list_satellites()
      
      started_count =
        satellites
        |> Enum.map(&start_satellite/1)
        |> Enum.count(fn result -> match?({:ok, _}, result) end)
      
      Logger.info("[SatelliteLoader] Started #{started_count}/#{length(satellites)} satellites")
    rescue
      e ->
        Logger.error("[SatelliteLoader] Failed to load satellites: #{inspect(e)}")
    end
  end
  
  defp start_satellite(satellite) do
    # Convert database ID to string for the GenServer
    id = to_string(satellite.id)
    
    # Note: Don't pass :name here - that's used for GenServer registration
    # The satellite's display name is stored in the State struct
    opts = [
      norad_id: satellite.norad_id,
      satellite_name: satellite.name
    ]
    
    case SatelliteSupervisor.start_satellite(id, opts) do
      {:ok, pid} ->
        Logger.debug("[SatelliteLoader] Started satellite #{id} (#{satellite.name})")
        {:ok, pid}
        
      {:error, :already_exists} ->
        Logger.debug("[SatelliteLoader] Satellite #{id} already running")
        {:ok, :already_exists}
        
      {:error, reason} ->
        Logger.warning("[SatelliteLoader] Failed to start satellite #{id}: #{inspect(reason)}")
        {:error, reason}
    end
  end
end
