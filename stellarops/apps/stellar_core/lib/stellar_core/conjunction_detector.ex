defmodule StellarCore.ConjunctionDetector do
  @moduledoc """
  GenServer for periodic conjunction detection.
  
  Periodically propagates orbits of all tracked objects and protected assets,
  calculates time of closest approach (TCA), miss distance, relative velocity,
  and probability of collision. Creates conjunction records and raises alarms
  for dangerous close approaches.
  """

  use GenServer
  require Logger

  alias StellarCore.Orbital
  alias StellarCore.Satellite
  alias StellarCore.Alarms
  alias StellarData.{Conjunctions, SpaceObjects, Threats}
  alias StellarData.Conjunctions.Conjunction

  @default_interval_ms 60_000 # 1 minute
  @default_horizon_hours 24
  @default_step_seconds 60

  # Miss distance thresholds in km by orbital regime
  @thresholds %{
    leo: %{critical: 1.0, high: 5.0, medium: 10.0},
    meo: %{critical: 5.0, high: 10.0, medium: 25.0},
    geo: %{critical: 10.0, high: 25.0, medium: 50.0}
  }

  # Altitude boundaries for regimes (km)
  @leo_max_altitude 2_000
  @meo_max_altitude 35_786

  defmodule State do
    @moduledoc false
    defstruct [:interval_ms, :horizon_hours, :step_seconds, :timer_ref, :thresholds]
  end

  # Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Trigger an immediate detection cycle (for testing or manual trigger).
  """
  def detect_now do
    GenServer.call(__MODULE__, :detect_now, 60_000)
  end

  @doc """
  Get current configuration.
  """
  def get_config do
    GenServer.call(__MODULE__, :get_config)
  end

  # Server callbacks

  @impl true
  def init(opts) do
    interval_ms = Keyword.get(opts, :interval_ms, @default_interval_ms)
    horizon_hours = Keyword.get(opts, :horizon_hours, @default_horizon_hours)
    step_seconds = Keyword.get(opts, :step_seconds, @default_step_seconds)
    thresholds = Keyword.get(opts, :thresholds, @thresholds)

    state = %State{
      interval_ms: interval_ms,
      horizon_hours: horizon_hours,
      step_seconds: step_seconds,
      thresholds: thresholds,
      timer_ref: nil
    }

    # Schedule first detection after startup
    {:ok, schedule_detection(state)}
  end

  @impl true
  def handle_call(:detect_now, _from, state) do
    result = perform_detection(state)
    {:reply, result, state}
  end

  @impl true
  def handle_call(:get_config, _from, state) do
    config = %{
      interval_ms: state.interval_ms,
      horizon_hours: state.horizon_hours,
      step_seconds: state.step_seconds
    }

    {:reply, config, state}
  end

  @impl true
  def handle_info(:detect, state) do
    perform_detection(state)
    {:noreply, schedule_detection(state)}
  end

  # Private functions

  defp schedule_detection(state) do
    # Cancel existing timer if any
    if state.timer_ref do
      Process.cancel_timer(state.timer_ref)
    end

    timer_ref = Process.send_after(self(), :detect, state.interval_ms)
    %{state | timer_ref: timer_ref}
  end

  defp perform_detection(state) do
    start_time = System.monotonic_time(:millisecond)

    Logger.info("Starting conjunction detection cycle")

    try do
      # Get all active satellites (our assets)
      assets = get_active_satellites()

      # Get all tracked space objects
      objects = SpaceObjects.list_objects()

      Logger.debug("Detecting conjunctions for #{length(assets)} assets vs #{length(objects)} objects")

      # Detect conjunctions for each asset
      results =
        Enum.flat_map(assets, fn asset ->
          detect_conjunctions_for_asset(asset, objects, state)
        end)

      # Expire past conjunctions
      {expired_count, _} = Conjunctions.expire_past_conjunctions()

      elapsed_ms = System.monotonic_time(:millisecond) - start_time

      Logger.info(
        "Conjunction detection complete: #{length(results)} conjunctions detected, " <>
          "#{expired_count} expired (#{elapsed_ms}ms)"
      )

      # Emit telemetry
      :telemetry.execute(
        [:stellar_core, :conjunction_detector, :cycle],
        %{duration: elapsed_ms, conjunctions_detected: length(results)},
        %{}
      )

      {:ok, %{detected: length(results), expired: expired_count}}
    rescue
      error ->
        Logger.error("Conjunction detection failed: #{inspect(error)}")
        {:error, error}
    end
  end

  defp get_active_satellites do
    # Get all satellites from the supervisor
    Satellite.Supervisor.list_satellites()
    |> Enum.map(fn satellite_id ->
      case Satellite.get_state(satellite_id) do
        {:ok, state} ->
          %{
            id: satellite_id,
            position: state.position,
            # For now, we'd need TLE stored on satellite or fetched from DB
            # This is a placeholder
            tle_line1: nil,
            tle_line2: nil
          }

        {:error, _} ->
          nil
      end
    end)
    |> Enum.reject(&is_nil/1)
  end

  defp detect_conjunctions_for_asset(asset, objects, state) do
    now = DateTime.utc_now()
    start_time = DateTime.to_unix(now)
    end_time = DateTime.to_unix(DateTime.add(now, state.horizon_hours * 3600, :second))

    # Skip if asset doesn't have TLE data
    if is_nil(asset.tle_line1) or is_nil(asset.tle_line2) do
      []
    else
      # Propagate asset trajectory
      case Orbital.propagate_trajectory(
             asset.id,
             asset.tle_line1,
             asset.tle_line2,
             start_time,
             end_time,
             state.step_seconds
           ) do
        {:ok, asset_trajectory} ->
          # Check each object
          Enum.flat_map(objects, fn object ->
            detect_conjunction(asset, asset_trajectory, object, state)
          end)

        {:error, reason} ->
          Logger.warning("Failed to propagate asset #{asset.id}: #{inspect(reason)}")
          []
      end
    end
  end

  defp detect_conjunction(asset, asset_trajectory, object, state) do
    # Skip if object doesn't have TLE
    if is_nil(object.tle_line1) or is_nil(object.tle_line2) do
      []
    else
      now = DateTime.utc_now()
      start_time = DateTime.to_unix(now)
      end_time = DateTime.to_unix(DateTime.add(now, state.horizon_hours * 3600, :second))

      # Propagate object trajectory
      case Orbital.propagate_trajectory(
             object.norad_id,
             object.tle_line1,
             object.tle_line2,
             start_time,
             end_time,
             state.step_seconds
           ) do
        {:ok, object_trajectory} ->
          # Find closest approach
          case find_closest_approach(asset_trajectory, object_trajectory) do
            {:ok, conjunction_data} ->
              # Create or update conjunction record
              handle_conjunction(asset, object, conjunction_data, state)

            {:error, :no_close_approach} ->
              []
          end

        {:error, reason} ->
          Logger.debug("Failed to propagate object #{object.norad_id}: #{inspect(reason)}")
          []
      end
    end
  end

  defp find_closest_approach(asset_trajectory, object_trajectory) do
    # Build maps of positions and velocities by timestamp for fast lookup
    object_data =
      Enum.into(object_trajectory, %{}, fn point ->
        {point.timestamp_unix, %{position: point.position, geodetic: point.geodetic}}
      end)

    asset_data =
      Enum.into(asset_trajectory, %{}, fn point ->
        {point.timestamp_unix, %{position: point.position, geodetic: point.geodetic}}
      end)

    # Find minimum distance between trajectories
    result =
      Enum.reduce_while(asset_trajectory, nil, fn asset_point, acc ->
        object_info = object_data[asset_point.timestamp_unix]

        if object_info do
          distance_km = calculate_distance(asset_point.position, object_info.position)

          # Estimate relative velocity from position changes
          rel_velocity = calculate_relative_velocity(
            asset_trajectory,
            object_trajectory,
            asset_point.timestamp_unix
          )

          new_acc =
            case acc do
              nil ->
                %{
                  distance_km: distance_km,
                  timestamp: asset_point.timestamp_unix,
                  asset_pos: asset_point.position,
                  object_pos: object_info.position,
                  asset_geodetic: asset_point.geodetic,
                  object_geodetic: object_info.geodetic,
                  relative_velocity_km_s: rel_velocity
                }

              %{distance_km: min_dist} when distance_km < min_dist ->
                %{
                  distance_km: distance_km,
                  timestamp: asset_point.timestamp_unix,
                  asset_pos: asset_point.position,
                  object_pos: object_info.position,
                  asset_geodetic: asset_point.geodetic,
                  object_geodetic: object_info.geodetic,
                  relative_velocity_km_s: rel_velocity
                }

              _ ->
                acc
            end

          {:cont, new_acc}
        else
          {:cont, acc}
        end
      end)

    case result do
      %{distance_km: dist, asset_geodetic: geodetic} ->
        # Check against regime-specific threshold
        max_threshold = get_max_threshold(geodetic.altitude_km)

        if dist < max_threshold do
          {:ok, result}
        else
          {:error, :no_close_approach}
        end

      _ ->
        {:error, :no_close_approach}
    end
  end

  defp calculate_distance(pos1, pos2) do
    dx = pos1.x_km - pos2.x_km
    dy = pos1.y_km - pos2.y_km
    dz = pos1.z_km - pos2.z_km
    :math.sqrt(dx * dx + dy * dy + dz * dz)
  end

  defp calculate_relative_velocity(asset_trajectory, object_trajectory, timestamp) do
    # Find the index of the current timestamp
    asset_index = Enum.find_index(asset_trajectory, &(&1.timestamp_unix == timestamp))
    object_by_ts = Enum.into(object_trajectory, %{}, &{&1.timestamp_unix, &1})

    if asset_index && asset_index > 0 do
      # Get current and previous points
      current_asset = Enum.at(asset_trajectory, asset_index)
      prev_asset = Enum.at(asset_trajectory, asset_index - 1)

      current_object = object_by_ts[current_asset.timestamp_unix]
      prev_object = object_by_ts[prev_asset.timestamp_unix]

      if current_object && prev_object do
        # Calculate position change for each object
        dt = current_asset.timestamp_unix - prev_asset.timestamp_unix

        if dt > 0 do
          # Asset velocity vector
          asset_dx = (current_asset.position.x_km - prev_asset.position.x_km) / dt
          asset_dy = (current_asset.position.y_km - prev_asset.position.y_km) / dt
          asset_dz = (current_asset.position.z_km - prev_asset.position.z_km) / dt

          # Object velocity vector
          object_dx = (current_object.position.x_km - prev_object.position.x_km) / dt
          object_dy = (current_object.position.y_km - prev_object.position.y_km) / dt
          object_dz = (current_object.position.z_km - prev_object.position.z_km) / dt

          # Relative velocity magnitude
          dvx = asset_dx - object_dx
          dvy = asset_dy - object_dy
          dvz = asset_dz - object_dz

          :math.sqrt(dvx * dvx + dvy * dvy + dvz * dvz)
        else
          0.0
        end
      else
        0.0
      end
    else
      0.0
    end
  end

  defp get_orbital_regime(altitude_km) do
    cond do
      altitude_km <= @leo_max_altitude -> :leo
      altitude_km <= @meo_max_altitude -> :meo
      true -> :geo
    end
  end

  defp get_max_threshold(altitude_km) do
    regime = get_orbital_regime(altitude_km)
    thresholds = @thresholds[regime]
    thresholds.medium
  end

  defp determine_severity(miss_distance_km, altitude_km, state) do
    regime = get_orbital_regime(altitude_km)
    thresholds = state.thresholds[regime]

    cond do
      miss_distance_km < thresholds.critical -> "critical"
      miss_distance_km < thresholds.high -> "high"
      miss_distance_km < thresholds.medium -> "medium"
      true -> "low"
    end
  end

  defp handle_conjunction(asset, object, conjunction_data, state) do
    tca = DateTime.from_unix!(conjunction_data.timestamp)
    miss_distance_km = conjunction_data.distance_km
    relative_velocity_km_s = conjunction_data.relative_velocity_km_s || 0.0
    altitude_km = conjunction_data.asset_geodetic.altitude_km

    severity = determine_severity(miss_distance_km, altitude_km, state)

    # Calculate simple probability based on miss distance and relative velocity
    # This is a simplified model - real probability requires covariance data
    probability = calculate_collision_probability(miss_distance_km, relative_velocity_km_s)

    attrs = %{
      asset_id: asset.id,
      object_id: object.id,
      tca: tca,
      miss_distance_km: miss_distance_km,
      relative_velocity_km_s: relative_velocity_km_s,
      probability_of_collision: probability,
      severity: severity,
      status: "active",
      asset_position_at_tca: %{
        x_km: conjunction_data.asset_pos.x_km,
        y_km: conjunction_data.asset_pos.y_km,
        z_km: conjunction_data.asset_pos.z_km
      },
      object_position_at_tca: %{
        x_km: conjunction_data.object_pos.x_km,
        y_km: conjunction_data.object_pos.y_km,
        z_km: conjunction_data.object_pos.z_km
      }
    }

    case Conjunctions.create_conjunction(attrs) do
      {:ok, conjunction} ->
        Logger.warning(
          "Conjunction detected: Asset #{asset.id} vs Object #{object.norad_id} " <>
            "at #{DateTime.to_iso8601(tca)}, miss distance: #{Float.round(miss_distance_km, 2)} km, " <>
            "relative velocity: #{Float.round(relative_velocity_km_s, 2)} km/s, " <>
            "severity: #{severity}, probability: #{Float.round(probability * 100, 4)}%"
        )

        # Raise alarm for critical/high severity conjunctions
        if severity in ["critical", "high"] do
          raise_conjunction_alarm(conjunction, asset, object)
        end

        # Publish PubSub event
        Phoenix.PubSub.broadcast(
          StellarData.PubSub,
          "conjunctions:all",
          {:conjunction_detected, conjunction}
        )

        Phoenix.PubSub.broadcast(
          StellarData.PubSub,
          "conjunctions:asset:#{asset.id}",
          {:conjunction_detected, conjunction}
        )

        [conjunction]

      {:error, changeset} ->
        Logger.error("Failed to create conjunction: #{inspect(changeset.errors)}")
        []
    end
  end

  defp calculate_collision_probability(miss_distance_km, relative_velocity_km_s) do
    # Simplified probability model using a Gaussian-like distribution
    # Real implementation would use covariance matrices and full CDM analysis
    
    # Assume a combined uncertainty radius (very simplified)
    uncertainty_km = 0.1 # 100 meters combined position uncertainty
    
    # Calculate probability based on miss distance relative to uncertainty
    # This is a very simplified model for demonstration
    sigma = uncertainty_km + (relative_velocity_km_s * 0.01) # Velocity adds uncertainty
    
    # Use exponential decay model
    probability = :math.exp(-1 * (miss_distance_km * miss_distance_km) / (2 * sigma * sigma))
    
    # Clamp to reasonable range
    min(probability, 1.0)
  end

  defp raise_conjunction_alarm(conjunction, asset, object) do
    details = %{
      conjunction_id: conjunction.id,
      asset_id: asset.id,
      object_norad_id: object.norad_id,
      object_name: object.name,
      tca: conjunction.tca,
      miss_distance_km: conjunction.miss_distance_km,
      severity: conjunction.severity
    }

    severity_atom =
      case conjunction.severity do
        "critical" -> :critical
        "high" -> :major
        _ -> :minor
      end

    Alarms.raise_alarm(
      severity_atom,
      "conjunction",
      "Conjunction detected: #{object.name} approaching #{asset.id}",
      "Asset #{asset.id}",
      details
    )
  end
end
