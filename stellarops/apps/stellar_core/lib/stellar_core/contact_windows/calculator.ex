defmodule StellarCore.ContactWindows.Calculator do
  @moduledoc """
  Contact window calculator for satellite-ground station visibility.

  Calculates when a satellite will be visible from a ground station
  based on orbital mechanics and minimum elevation constraints.

  Uses the Orbital service for SGP4 propagation and visibility calculations.
  """

  require Logger

  alias StellarCore.Orbital
  alias StellarData.GroundStations
  alias StellarData.Satellites
  alias StellarData.GroundStations.ContactWindow

  @default_lookahead_hours 24
  @min_pass_duration_seconds 60

  @doc """
  Calculate contact windows for a satellite with all ground stations.

  ## Parameters
    - satellite_id: The satellite identifier
    - opts: Options
      - `:lookahead_hours` - How far ahead to calculate (default: 24)
      - `:min_elevation_deg` - Minimum elevation override

  ## Returns
    - {:ok, [windows]} - List of contact windows
    - {:error, reason} - Error occurred
  """
  @spec calculate_for_satellite(String.t(), keyword()) :: {:ok, [map()]} | {:error, term()}
  def calculate_for_satellite(satellite_id, opts \\ []) do
    with {:ok, satellite} <- get_satellite_with_tle(satellite_id),
         {:ok, ground_stations} <- {:ok, GroundStations.list_active_ground_stations()} do
      lookahead = Keyword.get(opts, :lookahead_hours, @default_lookahead_hours)
      start_time = DateTime.utc_now()
      end_time = DateTime.add(start_time, lookahead, :hour)

      windows =
        ground_stations
        |> Task.async_stream(
          fn gs -> calculate_passes(satellite, gs, start_time, end_time, opts) end,
          max_concurrency: 10,
          timeout: 30_000
        )
        |> Enum.flat_map(fn
          {:ok, {:ok, passes}} -> passes
          {:ok, {:error, _}} -> []
          {:exit, _} -> []
        end)
        |> Enum.sort_by(& &1.aos_time)

      {:ok, windows}
    end
  end

  @doc """
  Calculate contact windows for a ground station with all satellites.

  ## Parameters
    - ground_station_id: The ground station identifier
    - opts: Options
      - `:lookahead_hours` - How far ahead to calculate (default: 24)

  ## Returns
    - {:ok, [windows]} - List of contact windows
    - {:error, reason} - Error occurred
  """
  @spec calculate_for_ground_station(binary(), keyword()) :: {:ok, [map()]} | {:error, term()}
  def calculate_for_ground_station(ground_station_id, opts \\ []) do
    with {:ok, ground_station} <- get_ground_station(ground_station_id),
         {:ok, satellites} <- {:ok, Satellites.list_active_satellites()} do
      lookahead = Keyword.get(opts, :lookahead_hours, @default_lookahead_hours)
      start_time = DateTime.utc_now()
      end_time = DateTime.add(start_time, lookahead, :hour)

      windows =
        satellites
        |> Enum.filter(&has_valid_tle?/1)
        |> Task.async_stream(
          fn sat -> calculate_passes(sat, ground_station, start_time, end_time, opts) end,
          max_concurrency: 10,
          timeout: 30_000
        )
        |> Enum.flat_map(fn
          {:ok, {:ok, passes}} -> passes
          {:ok, {:error, _}} -> []
          {:exit, _} -> []
        end)
        |> Enum.sort_by(& &1.aos_time)

      {:ok, windows}
    end
  end

  @doc """
  Calculate contact windows for a specific satellite-ground station pair.
  """
  @spec calculate_pair(String.t(), binary(), keyword()) :: {:ok, [map()]} | {:error, term()}
  def calculate_pair(satellite_id, ground_station_id, opts \\ []) do
    with {:ok, satellite} <- get_satellite_with_tle(satellite_id),
         {:ok, ground_station} <- get_ground_station(ground_station_id) do
      lookahead = Keyword.get(opts, :lookahead_hours, @default_lookahead_hours)
      start_time = DateTime.utc_now()
      end_time = DateTime.add(start_time, lookahead, :hour)

      calculate_passes(satellite, ground_station, start_time, end_time, opts)
    end
  end

  @doc """
  Calculate and persist contact windows for the next N hours.

  This is typically called periodically to keep the contact window
  database up to date.
  """
  @spec calculate_and_persist(keyword()) :: {:ok, non_neg_integer()} | {:error, term()}
  def calculate_and_persist(opts \\ []) do
    lookahead = Keyword.get(opts, :lookahead_hours, @default_lookahead_hours)

    satellites = Satellites.list_active_satellites() |> Enum.filter(&has_valid_tle?/1)
    ground_stations = GroundStations.list_active_ground_stations()

    Logger.info("[ContactWindows] Calculating windows",
      satellites: length(satellites),
      ground_stations: length(ground_stations),
      lookahead_hours: lookahead
    )

    start_time = DateTime.utc_now()
    end_time = DateTime.add(start_time, lookahead, :hour)

    # Delete old windows that have passed
    GroundStations.delete_past_contact_windows()

    count =
      for sat <- satellites, gs <- ground_stations, reduce: 0 do
        acc ->
          case calculate_passes(sat, gs, start_time, end_time, opts) do
            {:ok, passes} ->
              persisted =
                passes
                |> Enum.map(&persist_window/1)
                |> Enum.count(fn
                  {:ok, _} -> true
                  _ -> false
                end)

              acc + persisted

            {:error, _} ->
              acc
          end
      end

    Logger.info("[ContactWindows] Calculated #{count} windows")
    {:ok, count}
  end

  # Private Functions

  defp calculate_passes(satellite, ground_station, start_time, end_time, opts) do
    min_elevation = Keyword.get(opts, :min_elevation_deg, ground_station.min_elevation_deg || 10.0)

    gs_data = %{
      id: ground_station.id,
      name: ground_station.name,
      latitude_deg: ground_station.latitude_deg,
      longitude_deg: ground_station.longitude_deg,
      altitude_m: ground_station.altitude_m || 0,
      min_elevation_deg: min_elevation
    }

    case Orbital.calculate_visibility(
           satellite.id,
           satellite.tle_line1,
           satellite.tle_line2,
           gs_data,
           start_time,
           end_time
         ) do
      {:ok, passes} ->
        valid_passes =
          passes
          |> Enum.filter(&(&1.duration_seconds >= @min_pass_duration_seconds))
          |> Enum.map(fn pass ->
            %{
              satellite_id: satellite.id,
              satellite_name: satellite.name,
              ground_station_id: ground_station.id,
              ground_station_name: ground_station.name,
              aos_time: DateTime.from_unix!(pass.aos_timestamp),
              los_time: DateTime.from_unix!(pass.los_timestamp),
              max_elevation_time: DateTime.from_unix!(pass.max_elevation_timestamp),
              max_elevation_deg: pass.max_elevation_deg,
              aos_azimuth_deg: pass.aos_azimuth_deg,
              los_azimuth_deg: pass.los_azimuth_deg,
              duration_seconds: pass.duration_seconds
            }
          end)

        {:ok, valid_passes}

      {:error, reason} ->
        Logger.warning("Failed to calculate visibility",
          satellite_id: satellite.id,
          ground_station_id: ground_station.id,
          reason: reason
        )

        {:error, reason}
    end
  end

  defp persist_window(window) do
    attrs = %{
      satellite_id: window.satellite_id,
      ground_station_id: window.ground_station_id,
      aos_time: window.aos_time,
      los_time: window.los_time,
      max_elevation_time: window.max_elevation_time,
      max_elevation_deg: window.max_elevation_deg,
      aos_azimuth_deg: window.aos_azimuth_deg,
      los_azimuth_deg: window.los_azimuth_deg,
      duration_seconds: window.duration_seconds
    }

    GroundStations.create_or_update_contact_window(attrs)
  end

  defp get_satellite_with_tle(satellite_id) do
    case Satellites.get_satellite(satellite_id) do
      nil ->
        {:error, :satellite_not_found}

      satellite ->
        if has_valid_tle?(satellite) do
          {:ok, satellite}
        else
          {:error, :no_tle_data}
        end
    end
  end

  defp get_ground_station(ground_station_id) do
    case GroundStations.get_ground_station(ground_station_id) do
      nil -> {:error, :ground_station_not_found}
      gs -> {:ok, gs}
    end
  end

  defp has_valid_tle?(satellite) do
    satellite.tle_line1 != nil and satellite.tle_line2 != nil and
      byte_size(satellite.tle_line1 || "") >= 69 and
      byte_size(satellite.tle_line2 || "") >= 69
  end
end
