defmodule StellarCore.TLE.RefreshService do
  @moduledoc """
  Periodic TLE refresh service.

  Fetches updated Two-Line Element sets from external sources
  (e.g., CelesTrak, Space-Track) and updates the local database.

  ## Configuration

      config :stellar_core, StellarCore.TLE.RefreshService,
        enabled: true,
        refresh_interval_ms: 3_600_000,  # 1 hour
        sources: [
          {:celestrak, "https://celestrak.org/NORAD/elements/gp.php"}
        ]
  """

  use GenServer
  require Logger

  alias StellarData.Satellites

  @default_interval_ms 3_600_000  # 1 hour
  @http_timeout 30_000

  # Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Manually trigger a TLE refresh.
  """
  @spec refresh_now() :: :ok
  def refresh_now do
    GenServer.cast(__MODULE__, :refresh_now)
  end

  @doc """
  Get the status of the TLE refresh service.
  """
  @spec status() :: map()
  def status do
    GenServer.call(__MODULE__, :status)
  end

  @doc """
  Fetch TLE for a specific NORAD catalog ID.
  """
  @spec fetch_tle(String.t()) :: {:ok, map()} | {:error, term()}
  def fetch_tle(norad_id) do
    GenServer.call(__MODULE__, {:fetch_tle, norad_id}, @http_timeout)
  end

  # Server Callbacks

  @impl true
  def init(opts) do
    enabled = Keyword.get(opts, :enabled, config(:enabled, true))
    interval = Keyword.get(opts, :interval_ms, config(:refresh_interval_ms, @default_interval_ms))

    state = %{
      enabled: enabled,
      interval_ms: interval,
      last_refresh: nil,
      last_refresh_status: nil,
      refresh_count: 0,
      error_count: 0,
      timer_ref: nil
    }

    state =
      if enabled do
        # Schedule first refresh after a short delay
        ref = schedule_refresh(5_000)
        %{state | timer_ref: ref}
      else
        Logger.info("[TLE Refresh] Service disabled")
        state
      end

    Logger.info("[TLE Refresh] Service started", enabled: enabled, interval_ms: interval)
    {:ok, state}
  end

  @impl true
  def handle_cast(:refresh_now, state) do
    Logger.info("[TLE Refresh] Manual refresh triggered")
    new_state = do_refresh(state)
    {:noreply, new_state}
  end

  @impl true
  def handle_call(:status, _from, state) do
    status = %{
      enabled: state.enabled,
      interval_ms: state.interval_ms,
      last_refresh: state.last_refresh,
      last_refresh_status: state.last_refresh_status,
      refresh_count: state.refresh_count,
      error_count: state.error_count,
      next_refresh_in_ms: time_until_next_refresh(state)
    }

    {:reply, status, state}
  end

  @impl true
  def handle_call({:fetch_tle, norad_id}, _from, state) do
    result = fetch_single_tle(norad_id)
    {:reply, result, state}
  end

  @impl true
  def handle_info(:refresh, state) do
    new_state = do_refresh(state)

    # Schedule next refresh
    ref = schedule_refresh(new_state.interval_ms)
    {:noreply, %{new_state | timer_ref: ref}}
  end

  @impl true
  def handle_info({:ssl_closed, _}, state) do
    # Ignore SSL close messages
    {:noreply, state}
  end

  # Private Functions

  defp do_refresh(state) do
    start_time = System.monotonic_time(:millisecond)
    Logger.info("[TLE Refresh] Starting refresh cycle")

    result =
      try do
        refresh_all_satellites()
      rescue
        e ->
          Logger.error("[TLE Refresh] Refresh failed: #{inspect(e)}")
          {:error, :exception}
      end

    duration_ms = System.monotonic_time(:millisecond) - start_time

    case result do
      {:ok, count} ->
        Logger.info("[TLE Refresh] Refresh completed",
          updated_count: count,
          duration_ms: duration_ms
        )

        %{
          state
          | last_refresh: DateTime.utc_now(),
            last_refresh_status: :success,
            refresh_count: state.refresh_count + 1
        }

      {:error, reason} ->
        Logger.warning("[TLE Refresh] Refresh failed",
          reason: reason,
          duration_ms: duration_ms
        )

        %{
          state
          | last_refresh: DateTime.utc_now(),
            last_refresh_status: {:error, reason},
            error_count: state.error_count + 1
        }
    end
  end

  defp refresh_all_satellites do
    # Get all satellites that need TLE updates
    satellites = Satellites.list_satellites_needing_tle_update()

    updated_count =
      satellites
      |> Task.async_stream(
        fn sat -> update_satellite_tle(sat) end,
        max_concurrency: 5,
        timeout: @http_timeout
      )
      |> Enum.count(fn
        {:ok, :updated} -> true
        _ -> false
      end)

    {:ok, updated_count}
  end

  defp update_satellite_tle(satellite) do
    case fetch_single_tle(satellite.norad_id) do
      {:ok, tle_data} ->
        case Satellites.update_satellite(satellite, %{
               tle_line1: tle_data.line1,
               tle_line2: tle_data.line2,
               tle_epoch: tle_data.epoch,
               tle_updated_at: DateTime.utc_now()
             }) do
          {:ok, _} -> :updated
          {:error, _} -> :update_failed
        end

      {:error, _} ->
        :fetch_failed
    end
  end

  defp fetch_single_tle(norad_id) do
    # Try CelesTrak first
    url = "https://celestrak.org/NORAD/elements/gp.php?CATNR=#{norad_id}&FORMAT=TLE"

    :inets.start()
    :ssl.start()

    request = {String.to_charlist(url), [{~c"user-agent", ~c"StellarOps/1.0"}]}

    case :httpc.request(:get, request, [timeout: @http_timeout], body_format: :binary) do
      {:ok, {{_, 200, _}, _headers, body}} ->
        parse_tle_response(body)

      {:ok, {{_, status, _}, _, _}} ->
        {:error, {:http_error, status}}

      {:error, reason} ->
        {:error, {:connection_failed, reason}}
    end
  end

  defp parse_tle_response(body) when is_list(body), do: parse_tle_response(to_string(body))

  defp parse_tle_response(body) do
    lines =
      body
      |> String.trim()
      |> String.split("\n")
      |> Enum.map(&String.trim/1)

    case lines do
      [name, line1, line2] when byte_size(line1) >= 69 and byte_size(line2) >= 69 ->
        epoch = parse_tle_epoch(line1)

        {:ok,
         %{
           name: name,
           line1: line1,
           line2: line2,
           epoch: epoch
         }}

      [line1, line2] when byte_size(line1) >= 69 and byte_size(line2) >= 69 ->
        epoch = parse_tle_epoch(line1)

        {:ok,
         %{
           name: nil,
           line1: line1,
           line2: line2,
           epoch: epoch
         }}

      _ ->
        {:error, :invalid_tle_format}
    end
  end

  defp parse_tle_epoch(line1) do
    # TLE epoch is in columns 19-32 (0-indexed: 18-31)
    # Format: YYDDD.DDDDDDDD (year and day of year with fractional days)
    try do
      epoch_str = String.slice(line1, 18, 14)
      year_2digit = String.slice(epoch_str, 0, 2) |> String.to_integer()
      day_of_year = String.slice(epoch_str, 2, 12) |> String.to_float()

      # Convert 2-digit year (57-99 = 1957-1999, 00-56 = 2000-2056)
      year = if year_2digit >= 57, do: 1900 + year_2digit, else: 2000 + year_2digit

      # Convert to DateTime
      {:ok, jan1} = Date.new(year, 1, 1)
      days = trunc(day_of_year) - 1
      fractional_day = day_of_year - trunc(day_of_year)

      date = Date.add(jan1, days)
      seconds = trunc(fractional_day * 86400)

      {:ok, time} = Time.new(div(seconds, 3600), div(rem(seconds, 3600), 60), rem(seconds, 60))
      {:ok, dt} = DateTime.new(date, time, "Etc/UTC")
      dt
    rescue
      _ -> nil
    end
  end

  defp schedule_refresh(delay_ms) do
    Process.send_after(self(), :refresh, delay_ms)
  end

  defp time_until_next_refresh(%{timer_ref: nil}), do: nil

  defp time_until_next_refresh(%{timer_ref: ref}) do
    case Process.read_timer(ref) do
      false -> 0
      ms -> ms
    end
  end

  defp config(key, default) do
    Application.get_env(:stellar_core, __MODULE__, [])
    |> Keyword.get(key, default)
  end
end
