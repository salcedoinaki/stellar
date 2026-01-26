defmodule StellarCore.SSA.ConjunctionDetector do
  @moduledoc """
  GenServer for detecting potential conjunction events.

  Performs periodic screening of protected assets against the catalog
  of tracked space objects to identify potential collision threats.

  ## Features
  - Periodic all-on-all screening for protected assets
  - Configurable screening thresholds
  - Integration with Orbital service for propagation
  - Automatic severity classification
  - Real-time alerts via PubSub

  ## Configuration
  - :screening_interval_ms - Interval between screening runs (default: 5 minutes)
  - :prediction_window_hours - How far ahead to predict (default: 168 hours / 7 days)
  - :miss_distance_threshold_m - Initial screening distance (default: 10,000 m)
  """

  use GenServer
  require Logger

  alias StellarCore.Orbital
  alias StellarData.SpaceObjects
  alias StellarData.Conjunctions
  alias StellarData.Satellites

  @default_screening_interval_ms 5 * 60 * 1000  # 5 minutes
  @default_prediction_window_hours 168  # 7 days
  @default_miss_distance_threshold_m 10_000  # 10 km

  defstruct [
    :screening_interval_ms,
    :prediction_window_hours,
    :miss_distance_threshold_m,
    :last_screening_at,
    :conjunctions_found,
    :screening_in_progress
  ]

  # Client API

  @doc """
  Starts the ConjunctionDetector.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Triggers an immediate screening run (async).
  """
  def run_screening do
    GenServer.cast(__MODULE__, :run_screening)
  end

  @doc """
  Triggers an immediate screening run and waits for results (sync).
  Returns {:ok, results} or {:error, reason}.
  """
  def detect_now(timeout \\ 60_000) do
    GenServer.call(__MODULE__, :detect_now, timeout)
  end

  @doc """
  Gets the current detector status.
  """
  def get_status do
    GenServer.call(__MODULE__, :get_status)
  end

  @doc """
  Screens a specific satellite against all tracked objects.
  """
  def screen_satellite(satellite_id) do
    GenServer.call(__MODULE__, {:screen_satellite, satellite_id}, 60_000)
  end

  @doc """
  Gets screening results from the last run.
  """
  def get_last_results do
    GenServer.call(__MODULE__, :get_last_results)
  end

  @doc """
  Updates screening configuration.
  """
  def configure(opts) do
    GenServer.call(__MODULE__, {:configure, opts})
  end

  # Server Callbacks

  @impl true
  def init(opts) do
    state = %__MODULE__{
      screening_interval_ms: Keyword.get(opts, :screening_interval_ms, @default_screening_interval_ms),
      prediction_window_hours: Keyword.get(opts, :prediction_window_hours, @default_prediction_window_hours),
      miss_distance_threshold_m: Keyword.get(opts, :miss_distance_threshold_m, @default_miss_distance_threshold_m),
      last_screening_at: nil,
      conjunctions_found: 0,
      screening_in_progress: false
    }

    # Schedule first screening after startup delay
    Process.send_after(self(), :scheduled_screening, 30_000)

    Logger.info("[ConjunctionDetector] Started with #{state.prediction_window_hours}h prediction window")
    {:ok, state}
  end

  @impl true
  def handle_call(:get_status, _from, state) do
    status = %{
      screening_interval_ms: state.screening_interval_ms,
      prediction_window_hours: state.prediction_window_hours,
      miss_distance_threshold_m: state.miss_distance_threshold_m,
      last_screening_at: state.last_screening_at,
      conjunctions_found: state.conjunctions_found,
      screening_in_progress: state.screening_in_progress
    }
    {:reply, status, state}
  end

  @impl true
  def handle_call(:get_last_results, _from, state) do
    results = %{
      last_screening_at: state.last_screening_at,
      conjunctions_found: state.conjunctions_found
    }
    {:reply, results, state}
  end

  @impl true
  def handle_call({:screen_satellite, satellite_id}, _from, state) do
    result = do_screen_satellite(satellite_id, state)
    {:reply, result, state}
  end

  @impl true
  def handle_call({:configure, opts}, _from, state) do
    new_state = %{state |
      screening_interval_ms: Keyword.get(opts, :screening_interval_ms, state.screening_interval_ms),
      prediction_window_hours: Keyword.get(opts, :prediction_window_hours, state.prediction_window_hours),
      miss_distance_threshold_m: Keyword.get(opts, :miss_distance_threshold_m, state.miss_distance_threshold_m)
    }
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call(:detect_now, _from, %{screening_in_progress: true} = state) do
    {:reply, {:error, :screening_in_progress}, state}
  end

  @impl true
  def handle_call(:detect_now, _from, state) do
    # Run screening synchronously
    conjunctions_found = do_full_screening(state)
    
    new_state = %{state |
      last_screening_at: DateTime.utc_now(),
      conjunctions_found: conjunctions_found
    }

    result = {:ok, %{
      new_count: conjunctions_found,
      updated_count: 0,
      timestamp: DateTime.utc_now()
    }}

    {:reply, result, new_state}
  end

  @impl true
  def handle_cast(:run_screening, %{screening_in_progress: true} = state) do
    Logger.warn("[ConjunctionDetector] Screening already in progress, skipping")
    {:noreply, state}
  end

  @impl true
  def handle_cast(:run_screening, state) do
    {:noreply, start_screening(state)}
  end

  @impl true
  def handle_info(:scheduled_screening, state) do
    new_state = if state.screening_in_progress do
      Logger.debug("[ConjunctionDetector] Skipping scheduled screening, already in progress")
      state
    else
      start_screening(state)
    end

    # Schedule next screening
    Process.send_after(self(), :scheduled_screening, state.screening_interval_ms)
    {:noreply, new_state}
  end

  @impl true
  def handle_info({:screening_complete, conjunctions_found}, state) do
    Logger.debug("[ConjunctionDetector] Screening cycle finished, detected #{conjunctions_found} close approach(es)")
    
    new_state = %{state |
      screening_in_progress: false,
      last_screening_at: DateTime.utc_now(),
      conjunctions_found: conjunctions_found
    }

    # Broadcast results
    Phoenix.PubSub.broadcast(
      StellarCore.PubSub,
      "ssa:conjunctions",
      {:screening_complete, %{
        timestamp: DateTime.utc_now(),
        conjunctions_found: conjunctions_found
      }}
    )

    {:noreply, new_state}
  end

  @impl true
  def handle_info({:conjunction_detected, conjunction}, state) do
    # Broadcast individual conjunction alerts
    Phoenix.PubSub.broadcast(
      StellarCore.PubSub,
      "ssa:conjunctions",
      {:conjunction_detected, conjunction}
    )

    # If it's high severity, also broadcast to alerts channel
    if conjunction.severity in [:high, :critical] do
      Phoenix.PubSub.broadcast(
        StellarCore.PubSub,
        "alerts:global",
        {:critical_conjunction, conjunction}
      )
    end

    {:noreply, state}
  end

  # Private Functions

  defp start_screening(state) do
    parent = self()
    
    # Run screening in a separate process to avoid blocking
    Task.start(fn ->
      conjunctions_found = do_full_screening(state)
      send(parent, {:screening_complete, conjunctions_found})
    end)

    %{state | screening_in_progress: true}
  end

  defp do_full_screening(state) do
    Logger.info("[ConjunctionDetector] Starting full conjunction screening")
    
    start_time = System.monotonic_time(:millisecond)

    # Get all protected assets (our satellites)
    protected_assets = SpaceObjects.list_protected_assets()
    
    # Get all tracked objects
    all_objects = SpaceObjects.list_space_objects(limit: 10_000)

    # Filter out protected assets from secondary objects
    protected_ids = MapSet.new(protected_assets, & &1.id)
    secondary_objects = Enum.reject(all_objects, fn obj -> MapSet.member?(protected_ids, obj.id) end)

    # Screen each protected asset
    conjunctions = 
      protected_assets
      |> Enum.flat_map(fn primary ->
        screen_object_against_catalog(primary, secondary_objects, state)
      end)

    # Store conjunctions and send alerts
    Enum.each(conjunctions, fn conj ->
      case Conjunctions.upsert_conjunction(conj) do
        {:ok, saved} ->
          send(self(), {:conjunction_detected, saved})
        {:error, reason} ->
          Logger.error("[ConjunctionDetector] Failed to save conjunction: #{inspect(reason)}")
      end
    end)

    elapsed = System.monotonic_time(:millisecond) - start_time
    Logger.info("[ConjunctionDetector] Screening complete in #{elapsed}ms, detected #{length(conjunctions)} close approach(es)")

    length(conjunctions)
  end

  defp do_screen_satellite(satellite_id, state) do
    case Satellites.get_satellite(satellite_id) do
      nil ->
        {:error, :satellite_not_found}

      satellite ->
        # Get the corresponding space object if linked
        space_object = case SpaceObjects.get_by_norad_id(satellite.norad_id) do
          nil ->
            # Create a temporary object representation
            %{
              id: nil,
              norad_id: satellite.norad_id,
              tle_line1: satellite.tle_line1,
              tle_line2: satellite.tle_line2
            }
          obj -> obj
        end

        all_objects = SpaceObjects.list_space_objects(limit: 10_000)
        secondary_objects = Enum.reject(all_objects, fn obj -> 
          obj.norad_id == satellite.norad_id
        end)

        conjunctions = screen_object_against_catalog(space_object, secondary_objects, state)
        {:ok, conjunctions}
    end
  end

  defp screen_object_against_catalog(primary, secondary_objects, state) do
    # Get prediction time window
    end_time = DateTime.add(DateTime.utc_now(), state.prediction_window_hours * 3600, :second)
    
    # For each secondary object, check for close approaches
    secondary_objects
    |> Task.async_stream(fn secondary ->
      check_conjunction(primary, secondary, DateTime.utc_now(), end_time, state.miss_distance_threshold_m)
    end, max_concurrency: 10, timeout: 30_000)
    |> Enum.flat_map(fn
      {:ok, conjunctions} -> conjunctions
      {:exit, _reason} -> []
    end)
  end

  defp check_conjunction(primary, secondary, start_time, end_time, threshold_m) do
    # Skip if either object lacks TLE data
    if is_nil(primary.tle_line1) or is_nil(secondary.tle_line1) do
      []
    else
      # Use the Orbital service to predict trajectories
      case predict_close_approaches(primary, secondary, start_time, end_time, threshold_m) do
        {:ok, approaches} ->
          Enum.map(approaches, fn approach ->
            build_conjunction_attrs(primary, secondary, approach)
          end)
        {:error, _reason} ->
          []
      end
    end
  end

  defp predict_close_approaches(primary, secondary, start_time, end_time, threshold_m) do
    # Get trajectories for both objects
    # Using a coarse time step for initial screening
    step_minutes = 5
    duration_seconds = DateTime.diff(end_time, start_time)

    with {:ok, primary_trajectory} <- get_trajectory(primary, start_time, duration_seconds, step_minutes),
         {:ok, secondary_trajectory} <- get_trajectory(secondary, start_time, duration_seconds, step_minutes) do
      
      approaches = find_close_approaches(primary_trajectory, secondary_trajectory, threshold_m)
      {:ok, approaches}
    end
  end

  defp get_trajectory(object, start_time, duration_seconds, step_minutes) do
    Orbital.predict_trajectory(
      object.tle_line1,
      object.tle_line2,
      DateTime.to_iso8601(start_time),
      duration_seconds,
      step_minutes
    )
  end

  defp find_close_approaches(primary_trajectory, secondary_trajectory, threshold_m) do
    # Zip trajectories by timestamp and find close approaches
    # This is a simplified implementation - production would use more sophisticated algorithms
    
    primary_map = Map.new(primary_trajectory, fn p -> {p["timestamp"], p} end)
    
    secondary_trajectory
    |> Enum.filter(fn s ->
      case Map.get(primary_map, s["timestamp"]) do
        nil -> false
        p ->
          distance = calculate_distance(p, s)
          distance < threshold_m
      end
    end)
    |> Enum.map(fn s ->
      p = Map.get(primary_map, s["timestamp"])
      distance = calculate_distance(p, s)
      relative_velocity = calculate_relative_velocity(p, s)
      
      %{
        timestamp: s["timestamp"],
        miss_distance_m: distance,
        relative_velocity_ms: relative_velocity,
        primary_position: %{x: p["x"], y: p["y"], z: p["z"]},
        secondary_position: %{x: s["x"], y: s["y"], z: s["z"]}
      }
    end)
    |> refine_tca()
  end

  defp calculate_distance(p1, p2) do
    dx = (p1["x"] || 0) - (p2["x"] || 0)
    dy = (p1["y"] || 0) - (p2["y"] || 0)
    dz = (p1["z"] || 0) - (p2["z"] || 0)
    :math.sqrt(dx * dx + dy * dy + dz * dz) * 1000  # Convert km to m
  end

  defp calculate_relative_velocity(p1, p2) do
    dvx = (p1["vx"] || 0) - (p2["vx"] || 0)
    dvy = (p1["vy"] || 0) - (p2["vy"] || 0)
    dvz = (p1["vz"] || 0) - (p2["vz"] || 0)
    :math.sqrt(dvx * dvx + dvy * dvy + dvz * dvz) * 1000  # Convert km/s to m/s
  end

  # Group nearby approaches and find the minimum (TCA)
  defp refine_tca([]), do: []
  defp refine_tca(approaches) do
    # Group approaches within 1 hour of each other
    approaches
    |> Enum.sort_by(& &1.timestamp)
    |> Enum.chunk_while(
      [],
      fn approach, acc ->
        case acc do
          [] -> {:cont, [approach]}
          [first | _] = group ->
            # Parse timestamps and check if within 1 hour
            if timestamps_within_hours?(first.timestamp, approach.timestamp, 1) do
              {:cont, [approach | group]}
            else
              {:cont, Enum.reverse(group), [approach]}
            end
        end
      end,
      fn
        [] -> {:cont, []}
        group -> {:cont, Enum.reverse(group), []}
      end
    )
    |> Enum.map(fn group ->
      # Find the point with minimum distance (TCA)
      Enum.min_by(group, & &1.miss_distance_m)
    end)
  end

  defp timestamps_within_hours?(ts1, ts2, hours) do
    with {:ok, dt1, _} <- DateTime.from_iso8601(ts1),
         {:ok, dt2, _} <- DateTime.from_iso8601(ts2) do
      abs(DateTime.diff(dt1, dt2)) < hours * 3600
    else
      _ -> false
    end
  end

  defp build_conjunction_attrs(primary, secondary, approach) do
    {:ok, tca, _} = DateTime.from_iso8601(approach.timestamp)

    # Extract positions at TCA (already in km from trajectory propagation)
    primary_pos = approach.primary_position || %{}
    secondary_pos = approach.secondary_position || %{}

    %{
      primary_object_id: primary.id,
      secondary_object_id: secondary.id,
      satellite_id: primary.satellite_id,
      tca: tca,
      miss_distance_m: approach.miss_distance_m,
      relative_velocity_ms: approach.relative_velocity_ms,
      status: :predicted,
      data_source: "stellar_detector",
      screening_date: DateTime.utc_now(),
      last_updated: DateTime.utc_now(),
      # Position data at TCA (ECI coordinates in km)
      primary_position_x_km: primary_pos[:x],
      primary_position_y_km: primary_pos[:y],
      primary_position_z_km: primary_pos[:z],
      secondary_position_x_km: secondary_pos[:x],
      secondary_position_y_km: secondary_pos[:y],
      secondary_position_z_km: secondary_pos[:z]
    }
  end
end
