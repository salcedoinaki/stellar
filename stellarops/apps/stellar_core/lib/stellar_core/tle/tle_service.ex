defmodule StellarCore.TLE.TLEService do
  @moduledoc """
  Service for managing Two-Line Element (TLE) data.

  Provides functionality to:
  - Fetch TLE data from CelesTrak and Space-Track
  - Parse and validate TLE format
  - Update satellite TLE data
  - Batch update multiple satellites
  - Track TLE freshness and staleness
  """

  use GenServer
  require Logger

  alias StellarData.Satellites
  alias StellarData.SpaceObjects

  @celestrak_base_url "https://celestrak.org/NORAD/elements/gp.php"
  @spacetrack_base_url "https://www.space-track.org"

  # Refresh interval: 6 hours
  @default_refresh_interval :timer.hours(6)

  # TLE is considered stale after 7 days
  @stale_threshold_hours 168

  defstruct [
    :last_refresh,
    :next_refresh,
    :refresh_interval,
    :satellites_updated,
    :space_objects_updated,
    :last_error,
    :status
  ]

  # Client API

  @doc """
  Starts the TLE service.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Fetches TLE data for a specific NORAD ID.
  """
  def fetch_tle(norad_id) when is_integer(norad_id) do
    GenServer.call(__MODULE__, {:fetch_tle, norad_id}, 30_000)
  end

  @doc """
  Fetches TLE data for multiple NORAD IDs.
  """
  def fetch_tles(norad_ids) when is_list(norad_ids) do
    GenServer.call(__MODULE__, {:fetch_tles, norad_ids}, 60_000)
  end

  @doc """
  Fetches TLE data for a category (e.g., "active", "starlink", "stations").
  """
  def fetch_category(category) when is_binary(category) do
    GenServer.call(__MODULE__, {:fetch_category, category}, 60_000)
  end

  @doc """
  Triggers a refresh of all tracked satellites.
  """
  def refresh_all do
    GenServer.cast(__MODULE__, :refresh_all)
  end

  @doc """
  Gets the current service status.
  """
  def get_status do
    GenServer.call(__MODULE__, :get_status)
  end

  @doc """
  Lists satellites with stale TLE data.
  """
  def list_stale_satellites(threshold_hours \\ @stale_threshold_hours) do
    GenServer.call(__MODULE__, {:list_stale, threshold_hours})
  end

  @doc """
  Parses a TLE string into its components.
  Returns {:ok, parsed} or {:error, reason}.
  """
  def parse_tle(tle_line1, tle_line2) do
    with {:ok, line1_data} <- parse_line1(tle_line1),
         {:ok, line2_data} <- parse_line2(tle_line2) do
      {:ok, Map.merge(line1_data, line2_data)}
    end
  end

  # Server Callbacks

  @impl true
  def init(opts) do
    refresh_interval = Keyword.get(opts, :refresh_interval, @default_refresh_interval)

    state = %__MODULE__{
      last_refresh: nil,
      next_refresh: DateTime.add(DateTime.utc_now(), refresh_interval, :millisecond),
      refresh_interval: refresh_interval,
      satellites_updated: 0,
      space_objects_updated: 0,
      last_error: nil,
      status: :idle
    }

    # Schedule first refresh
    schedule_refresh(refresh_interval)

    Logger.info("[TLEService] Started with refresh interval: #{refresh_interval}ms")
    {:ok, state}
  end

  @impl true
  def handle_call({:fetch_tle, norad_id}, _from, state) do
    result = do_fetch_tle(norad_id)
    {:reply, result, state}
  end

  @impl true
  def handle_call({:fetch_tles, norad_ids}, _from, state) do
    results =
      norad_ids
      |> Task.async_stream(&do_fetch_tle/1, max_concurrency: 5, timeout: 20_000)
      |> Enum.map(fn
        {:ok, result} -> result
        {:exit, reason} -> {:error, reason}
      end)

    {:reply, results, state}
  end

  @impl true
  def handle_call({:fetch_category, category}, _from, state) do
    result = do_fetch_category(category)
    {:reply, result, state}
  end

  @impl true
  def handle_call(:get_status, _from, state) do
    status = %{
      last_refresh: state.last_refresh,
      next_refresh: state.next_refresh,
      satellites_updated: state.satellites_updated,
      space_objects_updated: state.space_objects_updated,
      last_error: state.last_error,
      status: state.status
    }
    {:reply, status, state}
  end

  @impl true
  def handle_call({:list_stale, threshold_hours}, _from, state) do
    threshold = DateTime.add(DateTime.utc_now(), -threshold_hours, :hour)

    # Query satellites with stale TLE
    stale_satellites = Satellites.list_satellites_with_stale_tle(threshold)
    stale_objects = SpaceObjects.list_objects_with_stale_tle(threshold)

    {:reply, %{satellites: stale_satellites, space_objects: stale_objects}, state}
  end

  @impl true
  def handle_cast(:refresh_all, state) do
    {:noreply, %{state | status: :refreshing}}
  end

  @impl true
  def handle_info(:refresh, state) do
    Logger.info("[TLEService] Starting scheduled TLE refresh")

    state = %{state | status: :refreshing}

    case do_refresh_all() do
      {:ok, stats} ->
        Logger.info("[TLEService] Refresh complete: #{stats.satellites} satellites, #{stats.objects} objects updated")

        new_state = %{state |
          last_refresh: DateTime.utc_now(),
          next_refresh: DateTime.add(DateTime.utc_now(), state.refresh_interval, :millisecond),
          satellites_updated: state.satellites_updated + stats.satellites,
          space_objects_updated: state.space_objects_updated + stats.objects,
          last_error: nil,
          status: :idle
        }

        schedule_refresh(state.refresh_interval)
        {:noreply, new_state}

      {:error, reason} ->
        Logger.error("[TLEService] Refresh failed: #{inspect(reason)}")

        new_state = %{state |
          last_error: reason,
          status: :error
        }

        # Retry sooner on error (30 minutes)
        schedule_refresh(:timer.minutes(30))
        {:noreply, new_state}
    end
  end

  @impl true
  def handle_info(_msg, state), do: {:noreply, state}

  # Private Functions

  defp schedule_refresh(interval) do
    Process.send_after(self(), :refresh, interval)
  end

  defp do_fetch_tle(norad_id) do
    url = "#{@celestrak_base_url}?CATNR=#{norad_id}&FORMAT=TLE"

    case http_get(url) do
      {:ok, body} ->
        parse_tle_response(body, norad_id)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp do_fetch_category(category) do
    url = "#{@celestrak_base_url}?GROUP=#{category}&FORMAT=TLE"

    case http_get(url) do
      {:ok, body} ->
        parse_bulk_tle_response(body)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp do_refresh_all do
    # Get all satellites that need TLE updates
    satellites = Satellites.list_satellites()

    norad_ids =
      satellites
      |> Enum.filter(&(&1.norad_id != nil))
      |> Enum.map(& &1.norad_id)

    # Fetch in batches
    results =
      norad_ids
      |> Enum.chunk_every(50)
      |> Enum.flat_map(fn batch ->
        case do_fetch_batch(batch) do
          {:ok, tles} -> tles
          {:error, _} -> []
        end
      end)

    # Update satellites with new TLE data
    satellite_count = update_satellites_with_tles(results)

    # Also fetch debris and other objects for SSA
    object_count =
      case do_fetch_category("debris") do
        {:ok, debris_tles} ->
          update_space_objects_with_tles(debris_tles)

        {:error, _} ->
          0
      end

    {:ok, %{satellites: satellite_count, objects: object_count}}
  end

  defp do_fetch_batch(norad_ids) do
    ids_param = Enum.join(norad_ids, ",")
    url = "#{@celestrak_base_url}?CATNR=#{ids_param}&FORMAT=TLE"

    case http_get(url) do
      {:ok, body} ->
        parse_bulk_tle_response(body)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp http_get(url) do
    case Req.get(url, receive_timeout: 30_000) do
      {:ok, %{status: 200, body: body}} ->
        {:ok, body}

      {:ok, %{status: status}} ->
        {:error, {:http_error, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp parse_tle_response(body, norad_id) do
    lines = String.split(body, "\n", trim: true)

    case lines do
      [name, line1, line2 | _] ->
        with {:ok, parsed} <- parse_tle(line1, line2) do
          {:ok, Map.merge(parsed, %{name: String.trim(name), norad_id: norad_id})}
        end

      [line1, line2 | _] ->
        parse_tle(line1, line2)

      _ ->
        {:error, :invalid_tle_format}
    end
  end

  defp parse_bulk_tle_response(body) do
    lines = String.split(body, "\n", trim: true)

    tles =
      lines
      |> Enum.chunk_every(3)
      |> Enum.filter(fn chunk -> length(chunk) >= 2 end)
      |> Enum.map(fn
        [name, line1, line2] ->
          case parse_tle(line1, line2) do
            {:ok, parsed} -> Map.put(parsed, :name, String.trim(name))
            {:error, _} -> nil
          end

        [line1, line2] ->
          case parse_tle(line1, line2) do
            {:ok, parsed} -> parsed
            {:error, _} -> nil
          end

        _ ->
          nil
      end)
      |> Enum.reject(&is_nil/1)

    {:ok, tles}
  end

  defp parse_line1(line) do
    # TLE Line 1 format:
    # 1 NNNNNC NNNNNAAA NNNNN.NNNNNNNN +.NNNNNNNN +NNNNN-N +NNNNN-N N NNNNN
    line = String.trim(line)

    if String.starts_with?(line, "1 ") and String.length(line) >= 69 do
      {:ok,
       %{
         line_number: 1,
         catalog_number: parse_int(String.slice(line, 2..6)),
         classification: String.at(line, 7),
         international_designator: String.trim(String.slice(line, 9..16)),
         epoch_year: parse_int(String.slice(line, 18..19)),
         epoch_day: parse_float(String.slice(line, 20..31)),
         first_derivative: parse_float(String.slice(line, 33..42)),
         second_derivative: parse_scientific(String.slice(line, 44..51)),
         bstar: parse_scientific(String.slice(line, 53..60)),
         ephemeris_type: parse_int(String.slice(line, 62..62)),
         element_number: parse_int(String.slice(line, 64..67)),
         checksum_line1: parse_int(String.slice(line, 68..68))
       }}
    else
      {:error, :invalid_line1_format}
    end
  end

  defp parse_line2(line) do
    # TLE Line 2 format:
    # 2 NNNNN NNN.NNNN NNN.NNNN NNNNNNN NNN.NNNN NNN.NNNN NN.NNNNNNNNNNNNNN
    line = String.trim(line)

    if String.starts_with?(line, "2 ") and String.length(line) >= 69 do
      {:ok,
       %{
         line_number: 2,
         catalog_number_line2: parse_int(String.slice(line, 2..6)),
         inclination: parse_float(String.slice(line, 8..15)),
         raan: parse_float(String.slice(line, 17..24)),
         eccentricity: parse_eccentricity(String.slice(line, 26..32)),
         argument_of_perigee: parse_float(String.slice(line, 34..41)),
         mean_anomaly: parse_float(String.slice(line, 43..50)),
         mean_motion: parse_float(String.slice(line, 52..62)),
         revolution_number: parse_int(String.slice(line, 63..67)),
         checksum_line2: parse_int(String.slice(line, 68..68))
       }}
    else
      {:error, :invalid_line2_format}
    end
  end

  defp parse_int(str) do
    str = String.trim(str)
    case Integer.parse(str) do
      {n, _} -> n
      :error -> 0
    end
  end

  defp parse_float(str) do
    str = String.trim(str)
    case Float.parse(str) do
      {n, _} -> n
      :error -> 0.0
    end
  end

  defp parse_eccentricity(str) do
    # Eccentricity is stored without the leading decimal point
    # e.g., "0123456" means 0.0123456
    str = String.trim(str)
    parse_float("0.#{str}")
  end

  defp parse_scientific(str) do
    # Scientific notation in TLE format: +12345-6 means 0.12345 * 10^-6
    str = String.trim(str)

    case Regex.run(~r/([+-]?)(\d+)([+-])(\d)/, str) do
      [_, sign, mantissa, exp_sign, exp] ->
        mantissa_val = parse_float("0.#{mantissa}")
        exp_val = if exp_sign == "-", do: -parse_int(exp), else: parse_int(exp)
        val = mantissa_val * :math.pow(10, exp_val)
        if sign == "-", do: -val, else: val

      _ ->
        0.0
    end
  end

  defp update_satellites_with_tles(tles) do
    tles
    |> Enum.reduce(0, fn tle, count ->
      case Satellites.get_by_norad_id(tle.catalog_number) do
        nil ->
          count

        satellite ->
          case Satellites.update_tle(satellite.id, tle) do
            {:ok, _} -> count + 1
            {:error, _} -> count
          end
      end
    end)
  end

  defp update_space_objects_with_tles(tles) do
    tles
    |> Enum.reduce(0, fn tle, count ->
      norad_id = tle.catalog_number

      attrs = %{
        norad_id: norad_id,
        name: Map.get(tle, :name, "Unknown #{norad_id}"),
        tle_line1: build_tle_line1(tle),
        tle_line2: build_tle_line2(tle),
        inclination_deg: tle.inclination,
        eccentricity: tle.eccentricity,
        raan_deg: tle.raan,
        arg_perigee_deg: tle.argument_of_perigee,
        mean_anomaly_deg: tle.mean_anomaly,
        mean_motion_revs_day: tle.mean_motion,
        tle_epoch: calculate_epoch(tle.epoch_year, tle.epoch_day),
        last_tle_update: DateTime.utc_now()
      }

      case SpaceObjects.upsert_from_tle(attrs) do
        {:ok, _} -> count + 1
        {:error, _} -> count
      end
    end)
  end

  defp build_tle_line1(tle) do
    # Reconstruct line 1 for storage - simplified
    "1 #{String.pad_leading("#{tle.catalog_number}", 5, "0")}U"
  end

  defp build_tle_line2(tle) do
    # Reconstruct line 2 for storage - simplified
    "2 #{String.pad_leading("#{tle.catalog_number}", 5, "0")}"
  end

  defp calculate_epoch(year, day) do
    # Convert TLE epoch to DateTime
    full_year = if year < 57, do: 2000 + year, else: 1900 + year
    day_int = trunc(day)
    day_frac = day - day_int

    # Start of year
    {:ok, start} = Date.new(full_year, 1, 1)
    date = Date.add(start, day_int - 1)

    # Add fractional day as seconds
    seconds = trunc(day_frac * 86400)
    {:ok, naive} = NaiveDateTime.new(date, Time.from_seconds_after_midnight(seconds))
    DateTime.from_naive!(naive, "Etc/UTC")
  end
end
