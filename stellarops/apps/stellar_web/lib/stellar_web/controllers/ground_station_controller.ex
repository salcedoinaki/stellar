defmodule StellarWeb.GroundStationController do
  @moduledoc """
  REST API controller for ground station management.
  """

  use StellarWeb, :controller

  alias StellarData.GroundStations
  alias StellarCore.Scheduler.DownlinkManager

  action_fallback StellarWeb.FallbackController

  @doc """
  GET /api/ground_stations
  List all ground stations.
  """
  def index(conn, _params) do
    stations = GroundStations.list_ground_stations()
    render(conn, :index, ground_stations: stations)
  end

  @doc """
  GET /api/ground_stations/:id
  Get a specific ground station.
  """
  def show(conn, %{"id" => id}) do
    case GroundStations.get_ground_station(id) do
      nil -> {:error, :not_found}
      station -> render(conn, :show, ground_station: station)
    end
  end

  @doc """
  POST /api/ground_stations
  Create a new ground station.
  """
  def create(conn, %{"ground_station" => station_params}) do
    case GroundStations.create_ground_station(station_params) do
      {:ok, station} ->
        conn
        |> put_status(:created)
        |> render(:show, ground_station: station)

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  @doc """
  PATCH /api/ground_stations/:id
  Update a ground station.
  """
  def update(conn, %{"id" => id, "ground_station" => station_params}) do
    with station when not is_nil(station) <- GroundStations.get_ground_station(id),
         {:ok, updated} <- GroundStations.update_ground_station(station, station_params) do
      render(conn, :show, ground_station: updated)
    else
      nil -> {:error, :not_found}
      {:error, changeset} -> {:error, changeset}
    end
  end

  @doc """
  DELETE /api/ground_stations/:id
  Delete a ground station.
  """
  def delete(conn, %{"id" => id}) do
    with station when not is_nil(station) <- GroundStations.get_ground_station(id),
         {:ok, _} <- GroundStations.delete_ground_station(station) do
      send_resp(conn, :no_content, "")
    else
      nil -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  PATCH /api/ground_stations/:id/status
  Update ground station status.
  """
  def set_status(conn, %{"id" => id, "status" => status}) do
    with station when not is_nil(station) <- GroundStations.get_ground_station(id),
         status_atom <- String.to_existing_atom(status),
         {:ok, updated} <- GroundStations.set_station_status(station, status_atom) do
      render(conn, :show, ground_station: updated)
    else
      nil -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  GET /api/ground_stations/bandwidth
  Get total available bandwidth.
  """
  def available_bandwidth(conn, _params) do
    bandwidth = DownlinkManager.available_bandwidth()
    json(conn, %{available_bandwidth_mbps: bandwidth})
  end

  @doc """
  GET /api/ground_stations/:id/windows
  Get contact windows for a ground station.
  """
  def windows(conn, %{"id" => id} = params) do
    start_time = parse_datetime(params["start"]) || DateTime.utc_now()
    hours = parse_int(params["hours"]) || 24
    end_time = DateTime.add(start_time, hours * 3600, :second)

    windows = GroundStations.get_station_windows(id, start_time, end_time)
    render(conn, :windows, windows: windows)
  end

  # ============================================================================
  # Private Helpers
  # ============================================================================

  defp parse_datetime(nil), do: nil

  defp parse_datetime(str) do
    case DateTime.from_iso8601(str) do
      {:ok, dt, _} -> dt
      _ -> nil
    end
  end

  defp parse_int(nil), do: nil

  defp parse_int(str) when is_binary(str) do
    case Integer.parse(str) do
      {int, _} -> int
      :error -> nil
    end
  end
end
