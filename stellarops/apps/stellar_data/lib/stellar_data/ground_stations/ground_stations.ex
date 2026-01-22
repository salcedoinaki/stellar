defmodule StellarData.GroundStations do
  @moduledoc """
  Context module for ground station and contact window management.

  Provides functions for managing ground stations and scheduling
  downlink windows for satellite communication.
  """

  import Ecto.Query
  alias StellarData.Repo
  alias StellarData.GroundStations.{GroundStation, ContactWindow}

  # ============================================================================
  # Ground Station CRUD
  # ============================================================================

  @doc """
  Creates a new ground station.
  """
  def create_ground_station(attrs) do
    %GroundStation{}
    |> GroundStation.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Gets a ground station by ID.
  """
  def get_ground_station(id) do
    Repo.get(GroundStation, id)
  end

  @doc """
  Gets a ground station by code.
  """
  def get_ground_station_by_code(code) do
    Repo.get_by(GroundStation, code: code)
  end

  @doc """
  Updates a ground station.
  """
  def update_ground_station(%GroundStation{} = station, attrs) do
    station
    |> GroundStation.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a ground station.
  """
  def delete_ground_station(%GroundStation{} = station) do
    Repo.delete(station)
  end

  @doc """
  Lists all ground stations.
  """
  def list_ground_stations do
    Repo.all(GroundStation)
  end

  @doc """
  Lists online ground stations.
  """
  def list_online_ground_stations do
    GroundStation
    |> where([g], g.status == :online)
    |> Repo.all()
  end

  @doc """
  Updates the status of a ground station.
  """
  def set_station_status(%GroundStation{} = station, status) do
    station
    |> GroundStation.status_changeset(status)
    |> Repo.update()
  end

  # ============================================================================
  # Contact Window Management
  # ============================================================================

  @doc """
  Creates a contact window.
  """
  def create_contact_window(attrs) do
    %ContactWindow{}
    |> ContactWindow.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Creates multiple contact windows in a batch.
  """
  def create_contact_windows(windows_attrs) do
    now = DateTime.utc_now()

    entries =
      Enum.map(windows_attrs, fn attrs ->
        attrs
        |> Map.put(:inserted_at, now)
        |> Map.put(:updated_at, now)
      end)

    Repo.insert_all(ContactWindow, entries, returning: true)
  end

  @doc """
  Gets a contact window by ID.
  """
  def get_contact_window(id) do
    Repo.get(ContactWindow, id)
  end

  @doc """
  Gets upcoming contact windows for a satellite.
  """
  def get_upcoming_windows(satellite_id, limit \\ 10) do
    now = DateTime.utc_now()

    ContactWindow
    |> where([w], w.satellite_id == ^satellite_id)
    |> where([w], w.aos > ^now)
    |> where([w], w.status == :scheduled)
    |> order_by([w], asc: w.aos)
    |> limit(^limit)
    |> preload(:ground_station)
    |> Repo.all()
  end

  @doc """
  Gets currently active contact windows.
  """
  def get_active_windows do
    now = DateTime.utc_now()

    ContactWindow
    |> where([w], w.aos <= ^now and w.los >= ^now)
    |> where([w], w.status in [:scheduled, :active])
    |> preload(:ground_station)
    |> Repo.all()
  end

  @doc """
  Gets contact windows for a ground station in a time range.
  """
  def get_station_windows(ground_station_id, start_time, end_time) do
    ContactWindow
    |> where([w], w.ground_station_id == ^ground_station_id)
    |> where([w], w.aos >= ^start_time and w.los <= ^end_time)
    |> order_by([w], asc: w.aos)
    |> Repo.all()
  end

  @doc """
  Allocates bandwidth for a contact window.
  """
  def allocate_bandwidth(%ContactWindow{} = window, bandwidth_mbps) do
    window
    |> ContactWindow.allocate_changeset(bandwidth_mbps)
    |> Repo.update()
  end

  @doc """
  Activates a contact window (starts data transfer).
  """
  def activate_window(%ContactWindow{} = window) do
    window
    |> ContactWindow.activate_changeset()
    |> Repo.update()
  end

  @doc """
  Completes a contact window with transfer stats.
  """
  def complete_window(%ContactWindow{} = window, data_transferred_mb) do
    window
    |> ContactWindow.complete_changeset(data_transferred_mb)
    |> Repo.update()
  end

  # ============================================================================
  # Downlink Scheduling
  # ============================================================================

  @doc """
  Finds the best contact window for a downlink mission.

  Considers:
  - Time constraints (deadline)
  - Required bandwidth
  - Ground station availability
  """
  def find_best_window(satellite_id, opts \\ []) do
    deadline = Keyword.get(opts, :deadline)
    min_bandwidth = Keyword.get(opts, :min_bandwidth, 0)
    min_duration = Keyword.get(opts, :min_duration, 60)

    now = DateTime.utc_now()

    query =
      ContactWindow
      |> join(:inner, [w], g in GroundStation, on: w.ground_station_id == g.id)
      |> where([w, _g], w.satellite_id == ^satellite_id)
      |> where([w, _g], w.status == :scheduled)
      |> where([w, _g], w.aos > ^now)
      |> where([w, _g], w.duration_seconds >= ^min_duration)
      |> where([w, g], g.status == :online)
      |> where([w, g], (g.bandwidth_mbps - w.allocated_bandwidth) >= ^min_bandwidth)
      |> order_by([w, _g], asc: w.aos)

    query =
      if deadline do
        where(query, [w, _g], w.aos < ^deadline)
      else
        query
      end

    query
    |> limit(1)
    |> preload(:ground_station)
    |> Repo.one()
  end

  @doc """
  Calculates total available bandwidth across all online ground stations.
  """
  def total_available_bandwidth do
    GroundStation
    |> where([g], g.status == :online)
    |> select([g], sum(g.bandwidth_mbps * (1 - g.current_load / 100)))
    |> Repo.one() || 0.0
  end

  @doc """
  Lists active (online) ground stations.
  """
  def list_active_ground_stations do
    list_online_ground_stations()
  end

  @doc """
  Lists upcoming contact windows within a time range.
  """
  def list_upcoming_contact_windows(start_time, end_time) do
    ContactWindow
    |> where([w], w.aos >= ^start_time and w.aos <= ^end_time)
    |> where([w], w.status == :scheduled)
    |> join(:inner, [w], g in GroundStation, on: w.ground_station_id == g.id)
    |> where([_w, g], g.status == :online)
    |> order_by([w, _g], asc: w.aos)
    |> preload(:ground_station)
    |> Repo.all()
  end

  @doc """
  Deletes contact windows that have passed (LOS < now).
  """
  def delete_past_contact_windows do
    now = DateTime.utc_now()

    ContactWindow
    |> where([w], w.los < ^now)
    |> where([w], w.status != :completed)
    |> Repo.delete_all()
  end

  @doc """
  Creates or updates a contact window based on satellite_id, ground_station_id, and aos_time.
  """
  def create_or_update_contact_window(attrs) do
    case find_contact_window(attrs.satellite_id, attrs.ground_station_id, attrs.aos_time) do
      nil ->
        create_contact_window(attrs)

      existing ->
        existing
        |> ContactWindow.changeset(attrs)
        |> Repo.update()
    end
  end

  defp find_contact_window(satellite_id, ground_station_id, aos_time) do
    # Find a window within 1 minute of the AOS time
    aos_start = DateTime.add(aos_time, -60, :second)
    aos_end = DateTime.add(aos_time, 60, :second)

    ContactWindow
    |> where([w], w.satellite_id == ^satellite_id)
    |> where([w], w.ground_station_id == ^ground_station_id)
    |> where([w], w.aos >= ^aos_start and w.aos <= ^aos_end)
    |> Repo.one()
  end
end
