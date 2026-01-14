defmodule StellarWeb.GroundStationJSON do
  @moduledoc """
  JSON rendering for ground stations and contact windows.
  """

  alias StellarData.GroundStations.{GroundStation, ContactWindow}

  def index(%{ground_stations: stations}) do
    %{data: for(station <- stations, do: station_data(station))}
  end

  def show(%{ground_station: station}) do
    %{data: station_data(station)}
  end

  def windows(%{windows: windows}) do
    %{data: for(window <- windows, do: window_data(window))}
  end

  defp station_data(%GroundStation{} = station) do
    %{
      id: station.id,
      name: station.name,
      code: station.code,
      description: station.description,
      # Location
      latitude: station.latitude,
      longitude: station.longitude,
      altitude: station.altitude,
      timezone: station.timezone,
      # Capabilities
      bandwidth_mbps: station.bandwidth_mbps,
      frequency_band: station.frequency_band,
      min_elevation: station.min_elevation,
      antenna_diameter: station.antenna_diameter,
      # Status
      status: station.status,
      current_load: station.current_load,
      # Timestamps
      inserted_at: station.inserted_at,
      updated_at: station.updated_at
    }
  end

  defp window_data(%ContactWindow{} = window) do
    %{
      id: window.id,
      satellite_id: window.satellite_id,
      ground_station_id: window.ground_station_id,
      # Time window
      aos: window.aos,
      los: window.los,
      tca: window.tca,
      duration_seconds: window.duration_seconds,
      # Pass characteristics
      max_elevation: window.max_elevation,
      aos_azimuth: window.aos_azimuth,
      los_azimuth: window.los_azimuth,
      # Allocation
      allocated_bandwidth: window.allocated_bandwidth,
      data_transferred: window.data_transferred,
      status: window.status,
      # Timestamps
      inserted_at: window.inserted_at,
      updated_at: window.updated_at
    }
  end
end
