defmodule StellarCore.TLEIngester do
  @moduledoc """
  Ingests TLE (Two-Line Element) data from external sources like CelesTrak and Space-Track.
  
  Supports:
  - Fetching active satellites, debris, and rocket body TLEs
  - Parsing TLE format into structured data
  - Matching and updating SpaceObject records
  - Periodic refresh with configurable intervals
  - Telemetry and alarm integration
  """
  
  use GenServer
  require Logger
  
  alias StellarCore.TLEIngester.{CelesTrakClient, SpaceTrackClient, TLEParser}
  alias StellarData.SSA
  
  @default_refresh_interval :timer.hours(6)
  @stale_threshold_hours 24
  
  # ============================================================================
  # Client API
  # ============================================================================
  
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @doc """
  Manually trigger TLE ingestion for all sources.
  """
  def ingest_all do
    GenServer.call(__MODULE__, :ingest_all, :timer.minutes(5))
  end
  
  @doc """
  Ingest TLEs from CelesTrak.
  """
  def ingest_celestrak(category \\ :active) do
    GenServer.call(__MODULE__, {:ingest_celestrak, category}, :timer.minutes(2))
  end
  
  @doc """
  Ingest TLEs from Space-Track.
  """
  def ingest_spacetrack(query \\ %{}) do
    GenServer.call(__MODULE__, {:ingest_spacetrack, query}, :timer.minutes(5))
  end
  
  @doc """
  Get the current ingestion status.
  """
  def status do
    GenServer.call(__MODULE__, :status)
  end
  
  @doc """
  Get statistics about TLE freshness.
  """
  def freshness_stats do
    GenServer.call(__MODULE__, :freshness_stats)
  end
  
  # ============================================================================
  # GenServer Callbacks
  # ============================================================================
  
  @impl true
  def init(opts) do
    refresh_interval = Keyword.get(opts, :refresh_interval, @default_refresh_interval)
    auto_start = Keyword.get(opts, :auto_start, true)
    
    state = %{
      refresh_interval: refresh_interval,
      last_ingestion: nil,
      last_error: nil,
      ingestion_count: 0,
      error_count: 0,
      enabled: auto_start
    }
    
    if auto_start do
      # Schedule initial ingestion after startup
      Process.send_after(self(), :scheduled_ingest, :timer.seconds(30))
    end
    
    Logger.info("TLEIngester started with refresh interval: #{div(refresh_interval, 60_000)} minutes")
    {:ok, state}
  end
  
  @impl true
  def handle_call(:ingest_all, _from, state) do
    result = do_ingest_all()
    new_state = update_state_after_ingestion(state, result)
    {:reply, result, new_state}
  end
  
  @impl true
  def handle_call({:ingest_celestrak, category}, _from, state) do
    result = do_ingest_celestrak(category)
    new_state = update_state_after_ingestion(state, result)
    {:reply, result, new_state}
  end
  
  @impl true
  def handle_call({:ingest_spacetrack, query}, _from, state) do
    result = do_ingest_spacetrack(query)
    new_state = update_state_after_ingestion(state, result)
    {:reply, result, new_state}
  end
  
  @impl true
  def handle_call(:status, _from, state) do
    {:reply, state, state}
  end
  
  @impl true
  def handle_call(:freshness_stats, _from, state) do
    stats = compute_freshness_stats()
    {:reply, stats, state}
  end
  
  @impl true
  def handle_info(:scheduled_ingest, state) do
    if state.enabled do
      Logger.info("Starting scheduled TLE ingestion")
      
      case do_ingest_all() do
        {:ok, _} ->
          Logger.info("Scheduled TLE ingestion completed successfully")
        {:error, reason} ->
          Logger.error("Scheduled TLE ingestion failed: #{inspect(reason)}")
      end
      
      # Check for stale TLEs and raise alarms
      check_stale_tles()
      
      # Schedule next ingestion
      Process.send_after(self(), :scheduled_ingest, state.refresh_interval)
    end
    
    {:noreply, state}
  end
  
  # ============================================================================
  # Private Functions
  # ============================================================================
  
  defp do_ingest_all do
    Logger.info("Starting full TLE ingestion from all sources")
    start_time = System.monotonic_time(:millisecond)
    
    results = [
      {:celestrak_active, do_ingest_celestrak(:active)},
      {:celestrak_debris, do_ingest_celestrak(:debris)},
      {:celestrak_rocket_bodies, do_ingest_celestrak(:rocket_bodies)},
      {:spacetrack, do_ingest_spacetrack(%{})}
    ]
    
    duration = System.monotonic_time(:millisecond) - start_time
    
    successes = Enum.count(results, fn {_, result} -> match?({:ok, _}, result) end)
    failures = Enum.count(results, fn {_, result} -> match?({:error, _}, result) end)
    
    total_ingested = 
      results
      |> Enum.filter(fn {_, result} -> match?({:ok, _}, result) end)
      |> Enum.map(fn {_, {:ok, count}} -> count end)
      |> Enum.sum()
    
    # Emit telemetry
    :telemetry.execute(
      [:stellar, :tle_ingestion, :complete],
      %{duration: duration, count: total_ingested},
      %{sources: successes, failures: failures}
    )
    
    Logger.info("TLE ingestion complete: #{total_ingested} TLEs in #{duration}ms (#{successes} sources succeeded, #{failures} failed)")
    
    if failures == 0 do
      {:ok, total_ingested}
    else
      {:partial, %{ingested: total_ingested, failures: failures, results: results}}
    end
  end
  
  defp do_ingest_celestrak(category) do
    Logger.debug("Fetching TLEs from CelesTrak: #{category}")
    
    with {:ok, tle_text} <- CelesTrakClient.fetch(category),
         {:ok, tles} <- TLEParser.parse_multi(tle_text),
         {:ok, count} <- upsert_tles(tles, :celestrak) do
      
      :telemetry.execute(
        [:stellar, :tle_ingestion, :source],
        %{count: count},
        %{source: :celestrak, category: category}
      )
      
      {:ok, count}
    else
      {:error, reason} = error ->
        :telemetry.execute(
          [:stellar, :tle_ingestion, :error],
          %{},
          %{source: :celestrak, category: category, reason: reason}
        )
        
        Logger.error("CelesTrak ingestion failed for #{category}: #{inspect(reason)}")
        error
    end
  end
  
  defp do_ingest_spacetrack(query) do
    Logger.debug("Fetching TLEs from Space-Track")
    
    with {:ok, tle_text} <- SpaceTrackClient.fetch(query),
         {:ok, tles} <- TLEParser.parse_multi(tle_text),
         {:ok, count} <- upsert_tles(tles, :spacetrack) do
      
      :telemetry.execute(
        [:stellar, :tle_ingestion, :source],
        %{count: count},
        %{source: :spacetrack}
      )
      
      {:ok, count}
    else
      {:error, reason} = error ->
        :telemetry.execute(
          [:stellar, :tle_ingestion, :error],
          %{},
          %{source: :spacetrack, reason: reason}
        )
        
        Logger.error("Space-Track ingestion failed: #{inspect(reason)}")
        error
    end
  end
  
  defp upsert_tles(tles, source) do
    count = 
      tles
      |> Enum.map(fn tle -> upsert_single_tle(tle, source) end)
      |> Enum.count(&match?({:ok, _}, &1))
    
    {:ok, count}
  end
  
  defp upsert_single_tle(tle, source) do
    norad_id = tle.norad_id
    
    attrs = %{
      norad_id: norad_id,
      name: tle.name,
      tle_line1: tle.line1,
      tle_line2: tle.line2,
      tle_epoch: tle.epoch,
      tle_source: source,
      tle_updated_at: DateTime.utc_now(),
      # Derived orbital elements
      inclination_deg: tle.inclination,
      eccentricity: tle.eccentricity,
      raan_deg: tle.raan,
      arg_perigee_deg: tle.arg_perigee,
      mean_anomaly_deg: tle.mean_anomaly,
      mean_motion: tle.mean_motion,
      period_min: 1440 / tle.mean_motion,
      apogee_km: compute_apogee(tle),
      perigee_km: compute_perigee(tle)
    }
    
    case SSA.get_space_object_by_norad_id(norad_id) do
      nil ->
        # Create new space object
        SSA.create_space_object(Map.put(attrs, :object_type, infer_object_type(tle)))
        
      existing ->
        # Update existing
        SSA.update_space_object(existing, attrs)
    end
  end
  
  defp compute_apogee(%{mean_motion: mm, eccentricity: e}) do
    # Semi-major axis from mean motion (revs/day)
    # a = (GM / (2π * n)^2)^(1/3) where n is rad/s
    earth_radius_km = 6371
    mu = 398600.4418  # km^3/s^2
    n_rad_s = mm * 2 * :math.pi() / 86400
    a = :math.pow(mu / (n_rad_s * n_rad_s), 1/3)
    a * (1 + e) - earth_radius_km
  end
  
  defp compute_perigee(%{mean_motion: mm, eccentricity: e}) do
    earth_radius_km = 6371
    mu = 398600.4418
    n_rad_s = mm * 2 * :math.pi() / 86400
    a = :math.pow(mu / (n_rad_s * n_rad_s), 1/3)
    a * (1 - e) - earth_radius_km
  end
  
  defp infer_object_type(%{name: name}) do
    cond do
      String.contains?(name, ["DEB", "DEBRIS"]) -> :debris
      String.contains?(name, ["R/B", "ROCKET"]) -> :rocket_body
      true -> :satellite
    end
  end
  
  defp update_state_after_ingestion(state, result) do
    case result do
      {:ok, _} ->
        %{state | 
          last_ingestion: DateTime.utc_now(),
          ingestion_count: state.ingestion_count + 1,
          last_error: nil
        }
        
      {:partial, _} ->
        %{state | 
          last_ingestion: DateTime.utc_now(),
          ingestion_count: state.ingestion_count + 1
        }
        
      {:error, reason} ->
        %{state | 
          error_count: state.error_count + 1,
          last_error: %{reason: reason, at: DateTime.utc_now()}
        }
    end
  end
  
  defp compute_freshness_stats do
    now = DateTime.utc_now()
    objects = SSA.list_space_objects()
    
    %{
      total: length(objects),
      with_tle: Enum.count(objects, & &1.tle_line1),
      fresh: Enum.count(objects, fn obj ->
        obj.tle_updated_at && 
        DateTime.diff(now, obj.tle_updated_at, :hour) < @stale_threshold_hours
      end),
      stale: Enum.count(objects, fn obj ->
        obj.tle_updated_at && 
        DateTime.diff(now, obj.tle_updated_at, :hour) >= @stale_threshold_hours
      end),
      never_updated: Enum.count(objects, &is_nil(&1.tle_updated_at))
    }
  end
  
  defp check_stale_tles do
    stats = compute_freshness_stats()
    
    if stats.stale > 0 do
      StellarCore.Alarms.raise_alarm(
        :stale_tle_data,
        "#{stats.stale} space objects have stale TLE data (>#{@stale_threshold_hours} hours old)",
        :warning,
        "tle_ingester",
        %{stale_count: stats.stale, threshold_hours: @stale_threshold_hours}
      )
    end
    
    if stats.stale > stats.total * 0.5 do
      StellarCore.Alarms.raise_alarm(
        :critical_tle_staleness,
        "Over 50% of space objects have stale TLE data",
        :major,
        "tle_ingester",
        %{stale_count: stats.stale, total: stats.total}
      )
    end
  end
end
