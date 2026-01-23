defmodule StellarCore.COAPlanner do
  @moduledoc """
  Course of Action (COA) Planner service.

  Generates possible maneuver options to respond to conjunction events.
  Each COA includes delta-V requirements, fuel consumption estimates,
  risk assessment, and predicted outcomes.

  ## COA Types

  - `:retrograde_burn` - Decrease velocity to lower orbit and change timing
  - `:prograde_burn` - Increase velocity to raise orbit and change timing
  - `:inclination_change` - Change orbital plane to avoid collision geometry
  - `:phasing` - Adjust orbital period to shift timing of conjunction
  - `:flyby` - Defensive intercept trajectory (for hostile threats)
  - `:station_keeping` - Maintain current orbit (accept risk)

  ## Risk Scoring

  COAs are scored 0-100 where lower is better:
  - Fuel consumption (normalized)
  - Time to execute vs time to TCA
  - Predicted miss distance improvement
  - Maneuver complexity
  - Satellite capability constraints
  """

  require Logger

  alias StellarData.COAs
  alias StellarData.Conjunctions
  alias StellarData.Satellites

  # Physical constants
  @earth_mu 398_600.4418  # km³/s² - Earth gravitational parameter
  @earth_radius 6371.0    # km - Mean Earth radius

  # Default satellite parameters (would come from asset database in production)
  @default_isp 300.0        # seconds - specific impulse
  @default_mass 500.0       # kg - satellite mass
  @default_fuel 50.0        # kg - available fuel

  # ============================================================================
  # Public Orbital Mechanics Functions (for testing)
  # ============================================================================

  @doc """
  Calculates orbital velocity using vis-viva equation.

  v = sqrt(mu * (2/r - 1/a))

  Where:
  - r: current radius from Earth center (km)
  - a: semi-major axis (km)
  - mu: gravitational parameter (km³/s²)
  """
  def vis_viva(r, a, mu \\ @earth_mu) do
    :math.sqrt(mu * (2 / r - 1 / a))
  end

  @doc """
  Calculates delta-V for Hohmann transfer between two circular orbits.

  Returns {dv1, dv2} for the two burns.
  """
  def hohmann_dv(r1, r2, mu \\ @earth_mu) do
    # Transfer orbit semi-major axis
    a_transfer = (r1 + r2) / 2

    # Velocities at departure and arrival
    v1_circular = :math.sqrt(mu / r1)
    v2_circular = :math.sqrt(mu / r2)

    # Velocities in transfer orbit at periapsis and apoapsis
    v1_transfer = :math.sqrt(mu * (2 / r1 - 1 / a_transfer))
    v2_transfer = :math.sqrt(mu * (2 / r2 - 1 / a_transfer))

    dv1 = abs(v1_transfer - v1_circular)
    dv2 = abs(v2_circular - v2_transfer)

    {dv1, dv2}
  end

  @doc """
  Calculates delta-V for inclination change.

  dv = 2 * v * sin(di/2)
  """
  def inclination_change_dv(velocity, delta_i_degrees) do
    delta_i_rad = delta_i_degrees * :math.pi() / 180.0
    2 * velocity * :math.sin(delta_i_rad / 2)
  end

  @doc """
  Calculates fuel consumption using Tsiolkovsky rocket equation.

  m_fuel = m0 * (1 - e^(-dv / ve))
  where ve = Isp * g0
  """
  def estimate_fuel(delta_v, spacecraft_mass, isp \\ @default_isp) do
    g0 = 0.00981  # km/s²
    ve = isp * g0

    spacecraft_mass * (1 - :math.exp(-delta_v / ve))
  end

  @doc """
  Estimates burn duration based on thrust and mass.
  """
  def estimate_burn_duration(delta_v_km_s, thrust_n, mass_kg) do
    # a = F/m, t = dv/a
    delta_v_m_s = delta_v_km_s * 1000
    acceleration = thrust_n / mass_kg
    delta_v_m_s / acceleration
  end

  @doc """
  Calculates risk score for a COA.

  Factors:
  - Fuel consumption (30%)
  - Time to TCA (40%)
  - Improvement factor (30%)
  """
  def calculate_risk_score(fuel_kg, time_to_tca_seconds, improvement_factor) do
    # Normalize fuel (assume 50kg max)
    fuel_score = min(fuel_kg / @default_fuel * 100, 100)

    # Time score (more time = lower risk)
    time_score = cond do
      time_to_tca_seconds < 3600 -> 100.0
      time_to_tca_seconds < 7200 -> 80.0
      time_to_tca_seconds < 14400 -> 60.0
      time_to_tca_seconds < 43200 -> 40.0
      time_to_tca_seconds < 86400 -> 20.0
      true -> 10.0
    end

    # Improvement score (higher improvement = lower risk)
    improvement_score = (1 - improvement_factor) * 100

    fuel_score * 0.3 + time_score * 0.4 + improvement_score * 0.3
  end

  @doc """
  Builds a retrograde burn COA from conjunction and orbit data.
  """
  def build_retrograde_coa(conjunction, satellite_orbit) do
    altitude = (satellite_orbit["a"] || 6771.0) - @earth_radius
    velocity = :math.sqrt(@earth_mu / (altitude + @earth_radius))

    # Target: lower by 10 km
    target_r = altitude + @earth_radius - 10.0
    target_v = :math.sqrt(@earth_mu / target_r)
    delta_v = abs(velocity - target_v)

    fuel_kg = estimate_fuel(delta_v, conjunction.asset.mass_kg || @default_mass)
    time_to_tca = DateTime.diff(conjunction.tca, DateTime.utc_now(), :second)
    improvement = 0.7

    %{
      conjunction_id: conjunction.id,
      type: :retrograde_burn,
      name: "Retrograde Burn",
      objective: "Lower orbit to change timing",
      delta_v_magnitude: Float.round(delta_v, 4),
      delta_v_direction: %{"x" => -1.0, "y" => 0.0, "z" => 0.0},
      burn_start_time: DateTime.add(conjunction.tca, -3600, :second),
      burn_duration_seconds: delta_v * 1000 / 0.1,
      estimated_fuel_kg: Float.round(fuel_kg, 3),
      predicted_miss_distance_km: conjunction.miss_distance_km + 5.0,
      risk_score: calculate_risk_score(fuel_kg, time_to_tca, improvement),
      pre_burn_orbit: satellite_orbit,
      post_burn_orbit: Map.put(satellite_orbit, "a", target_r),
      status: :proposed
    }
  end

  @doc """
  Builds an inclination change COA.
  """
  def build_inclination_change_coa(conjunction, satellite_orbit) do
    altitude = (satellite_orbit["a"] || 6771.0) - @earth_radius
    velocity = :math.sqrt(@earth_mu / (altitude + @earth_radius))

    delta_i = 0.1  # degrees
    delta_v = inclination_change_dv(velocity, delta_i)

    fuel_kg = estimate_fuel(delta_v, conjunction.asset.mass_kg || @default_mass)
    time_to_tca = DateTime.diff(conjunction.tca, DateTime.utc_now(), :second)

    new_i = (satellite_orbit["i"] || 45.0) + delta_i

    %{
      conjunction_id: conjunction.id,
      type: :inclination_change,
      name: "Inclination Change",
      objective: "Change orbital plane",
      delta_v_magnitude: Float.round(delta_v, 4),
      delta_v_direction: %{"x" => 0.0, "y" => 0.0, "z" => 1.0},
      burn_start_time: DateTime.add(conjunction.tca, -7200, :second),
      burn_duration_seconds: delta_v * 1000 / 0.1,
      estimated_fuel_kg: Float.round(fuel_kg, 3),
      predicted_miss_distance_km: conjunction.miss_distance_km + 20.0,
      risk_score: calculate_risk_score(fuel_kg, time_to_tca, 0.9),
      pre_burn_orbit: satellite_orbit,
      post_burn_orbit: Map.put(satellite_orbit, "i", new_i),
      status: :proposed
    }
  end

  @doc """
  Builds a station keeping COA (no maneuver).
  """
  def build_station_keeping_coa(conjunction, satellite_orbit) do
    time_to_tca = DateTime.diff(conjunction.tca, DateTime.utc_now(), :second)

    %{
      conjunction_id: conjunction.id,
      type: :station_keeping,
      name: "Station Keeping",
      objective: "Maintain current orbit",
      delta_v_magnitude: 0.0,
      delta_v_direction: %{"x" => 0.0, "y" => 0.0, "z" => 0.0},
      burn_start_time: nil,
      burn_duration_seconds: 0.0,
      estimated_fuel_kg: 0.0,
      predicted_miss_distance_km: conjunction.miss_distance_km,
      risk_score: calculate_risk_score(0.0, time_to_tca, 0.0),
      pre_burn_orbit: satellite_orbit,
      post_burn_orbit: satellite_orbit,
      status: :proposed
    }
  end

  # TASK-315: Generate COAs for a conjunction
  @doc """
  Generates a list of COAs for a given conjunction.

  Returns a list of COA maps ready to be inserted into the database.
  """
  def generate_coas(conjunction_id) do
    start_time = System.monotonic_time(:millisecond)

    with conjunction when not is_nil(conjunction) <- Conjunctions.get_conjunction(conjunction_id),
         {:ok, asset} <- get_asset(conjunction.asset_id) do

      # Clear any existing proposed COAs
      COAs.clear_proposed_coas(conjunction_id)

      # Generate each type of COA
      coas = [
        calculate_retrograde_burn(conjunction, asset),
        calculate_prograde_burn(conjunction, asset),
        calculate_inclination_change(conjunction, asset),
        calculate_phasing_maneuver(conjunction, asset),
        calculate_station_keeping(conjunction, asset)
      ]
      |> Enum.filter(&(&1 != nil))
      |> Enum.map(&add_risk_score(&1, conjunction, asset))
      |> rank_by_risk()

      # Insert COAs into database
      inserted_coas = Enum.map(coas, fn coa_attrs ->
        case COAs.create_coa(coa_attrs) do
          {:ok, coa} -> coa
          {:error, _} -> nil
        end
      end)
      |> Enum.filter(&(&1 != nil))

      # Emit telemetry
      duration = System.monotonic_time(:millisecond) - start_time
      :telemetry.execute(
        [:stellar_core, :coa_planner, :generate],
        %{duration: duration, count: length(inserted_coas)},
        %{conjunction_id: conjunction_id}
      )

      {:ok, inserted_coas}
    else
      nil -> {:error, :conjunction_not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  # TASK-316-320: Retrograde burn calculation
  @doc """
  Calculates a retrograde burn COA to lower orbit and change timing.
  """
  def calculate_retrograde_burn(conjunction, asset) do
    tca = conjunction.tca
    miss_distance = conjunction.miss_distance_km
    time_to_tca = DateTime.diff(tca, DateTime.utc_now(), :second)

    # Skip if TCA is too soon (need at least 2 hours)
    if time_to_tca < 7200, do: nil, else: do_retrograde_burn(conjunction, asset, time_to_tca)
  end

  defp do_retrograde_burn(conjunction, asset, time_to_tca) do
    # TASK-317: Calculate required ΔV
    # Simple model: lower perigee by ~10 km to change timing
    altitude = get_altitude(asset)
    orbital_velocity = calculate_orbital_velocity(altitude)

    # ΔV for lowering perigee by 10 km (vis-viva)
    target_altitude = altitude - 10.0
    target_velocity = calculate_orbital_velocity(target_altitude)
    delta_v = abs(orbital_velocity - target_velocity)

    # TASK-318: Optimal burn time (1/4 orbit before TCA)
    orbital_period = calculate_orbital_period(altitude)
    burn_lead_time = min(orbital_period / 4, time_to_tca * 0.5)
    burn_start = DateTime.add(conjunction.tca, -round(burn_lead_time), :second)

    # TASK-319: Fuel consumption
    fuel_kg = calculate_fuel_consumption(delta_v, @default_mass, @default_isp)

    # Burn duration (assuming 0.1 m/s² acceleration)
    burn_duration = delta_v * 1000 / 0.1  # seconds

    # TASK-320: Predicted miss distance improvement
    # Simplified: assume 10 km timing change adds ~5 km to miss distance
    predicted_miss = conjunction.miss_distance_km + 5.0

    %{
      conjunction_id: conjunction.id,
      type: :retrograde_burn,
      name: "Retrograde Burn",
      objective: "Lower orbit to change timing and avoid conjunction",
      description: "Decrease orbital velocity to lower perigee, shifting orbital timing relative to threat object.",
      delta_v_magnitude: Float.round(delta_v, 4),
      delta_v_direction: %{"x" => -1.0, "y" => 0.0, "z" => 0.0},  # Retrograde
      burn_start_time: burn_start,
      burn_duration_seconds: Float.round(burn_duration, 2),
      estimated_fuel_kg: Float.round(fuel_kg, 3),
      predicted_miss_distance_km: Float.round(predicted_miss, 2),
      pre_burn_orbit: get_orbital_elements(asset),
      post_burn_orbit: calculate_post_burn_orbit(asset, -delta_v),
      status: :proposed
    }
  end

  # Prograde burn (opposite of retrograde)
  defp calculate_prograde_burn(conjunction, asset) do
    tca = conjunction.tca
    time_to_tca = DateTime.diff(tca, DateTime.utc_now(), :second)

    if time_to_tca < 7200, do: nil, else: do_prograde_burn(conjunction, asset, time_to_tca)
  end

  defp do_prograde_burn(conjunction, asset, time_to_tca) do
    altitude = get_altitude(asset)
    orbital_velocity = calculate_orbital_velocity(altitude)

    # Raise apogee by 10 km
    target_altitude = altitude + 10.0
    target_velocity = calculate_orbital_velocity(target_altitude)
    delta_v = abs(target_velocity - orbital_velocity)

    orbital_period = calculate_orbital_period(altitude)
    burn_lead_time = min(orbital_period / 4, time_to_tca * 0.5)
    burn_start = DateTime.add(conjunction.tca, -round(burn_lead_time), :second)

    fuel_kg = calculate_fuel_consumption(delta_v, @default_mass, @default_isp)
    burn_duration = delta_v * 1000 / 0.1

    predicted_miss = conjunction.miss_distance_km + 5.0

    %{
      conjunction_id: conjunction.id,
      type: :prograde_burn,
      name: "Prograde Burn",
      objective: "Raise orbit to change timing and avoid conjunction",
      description: "Increase orbital velocity to raise apogee, shifting orbital timing relative to threat object.",
      delta_v_magnitude: Float.round(delta_v, 4),
      delta_v_direction: %{"x" => 1.0, "y" => 0.0, "z" => 0.0},  # Prograde
      burn_start_time: burn_start,
      burn_duration_seconds: Float.round(burn_duration, 2),
      estimated_fuel_kg: Float.round(fuel_kg, 3),
      predicted_miss_distance_km: Float.round(predicted_miss, 2),
      pre_burn_orbit: get_orbital_elements(asset),
      post_burn_orbit: calculate_post_burn_orbit(asset, delta_v),
      status: :proposed
    }
  end

  # TASK-321-324: Inclination change calculation
  @doc """
  Calculates an inclination change COA.

  This is typically the most expensive maneuver but can completely
  avoid the collision geometry.
  """
  def calculate_inclination_change(conjunction, asset) do
    time_to_tca = DateTime.diff(conjunction.tca, DateTime.utc_now(), :second)

    # Need more time for plane changes
    if time_to_tca < 14400, do: nil, else: do_inclination_change(conjunction, asset)
  end

  defp do_inclination_change(conjunction, asset) do
    altitude = get_altitude(asset)
    orbital_velocity = calculate_orbital_velocity(altitude)

    # TASK-322: Calculate plane change ΔV
    # Small inclination change of 0.1 degrees
    inclination_change_rad = 0.1 * :math.pi() / 180.0
    delta_v = 2 * orbital_velocity * :math.sin(inclination_change_rad / 2)

    # TASK-323: Best time is at ascending/descending node
    # Simplified: use 1 orbit before TCA
    orbital_period = calculate_orbital_period(altitude)
    burn_start = DateTime.add(conjunction.tca, -round(orbital_period), :second)

    # TASK-324: Fuel consumption (typically 3-5x radial burns)
    fuel_kg = calculate_fuel_consumption(delta_v, @default_mass, @default_isp)
    burn_duration = delta_v * 1000 / 0.1

    # Plane change is very effective at avoiding collisions
    predicted_miss = conjunction.miss_distance_km + 20.0

    %{
      conjunction_id: conjunction.id,
      type: :inclination_change,
      name: "Inclination Change",
      objective: "Change orbital plane to avoid collision geometry",
      description: "Perform out-of-plane maneuver at orbital node to change inclination and avoid conjunction point.",
      delta_v_magnitude: Float.round(delta_v, 4),
      delta_v_direction: %{"x" => 0.0, "y" => 0.0, "z" => 1.0},  # Out-of-plane
      burn_start_time: burn_start,
      burn_duration_seconds: Float.round(burn_duration, 2),
      estimated_fuel_kg: Float.round(fuel_kg, 3),
      predicted_miss_distance_km: Float.round(predicted_miss, 2),
      pre_burn_orbit: get_orbital_elements(asset),
      post_burn_orbit: Map.put(get_orbital_elements(asset), "i", get_orbital_elements(asset)["i"] + 0.1),
      status: :proposed
    }
  end

  # TASK-325-327: Phasing maneuver calculation
  @doc """
  Calculates a phasing maneuver COA.

  Uses a temporary higher/lower orbit to shift the satellite's
  position along the orbit track.
  """
  def calculate_phasing_maneuver(conjunction, asset) do
    time_to_tca = DateTime.diff(conjunction.tca, DateTime.utc_now(), :second)

    # Need at least 2 orbits for phasing
    altitude = get_altitude(asset)
    orbital_period = calculate_orbital_period(altitude)

    if time_to_tca < 2 * orbital_period, do: nil, else: do_phasing(conjunction, asset, orbital_period)
  end

  defp do_phasing(conjunction, asset, orbital_period) do
    altitude = get_altitude(asset)
    orbital_velocity = calculate_orbital_velocity(altitude)

    # TASK-326: ΔV for phasing orbit (slightly different period)
    # Change period by 1% requires small ΔV
    delta_v = orbital_velocity * 0.005  # ~0.5% velocity change

    # TASK-327: Number of orbits for phasing
    # Simplified: use 2 orbits in phasing orbit
    phasing_orbits = 2
    burn_start = DateTime.add(conjunction.tca, -round(phasing_orbits * orbital_period), :second)

    fuel_kg = calculate_fuel_consumption(delta_v * 2, @default_mass, @default_isp)  # Two burns
    burn_duration = delta_v * 1000 / 0.1

    predicted_miss = conjunction.miss_distance_km + 8.0

    %{
      conjunction_id: conjunction.id,
      type: :phasing,
      name: "Phasing Maneuver",
      objective: "Shift orbital position to avoid conjunction timing",
      description: "Enter temporary phasing orbit to adjust position along orbit track, avoiding collision point timing.",
      delta_v_magnitude: Float.round(delta_v * 2, 4),  # Total for both burns
      delta_v_direction: %{"x" => 1.0, "y" => 0.0, "z" => 0.0},
      burn_start_time: burn_start,
      burn_duration_seconds: Float.round(burn_duration * 2, 2),
      estimated_fuel_kg: Float.round(fuel_kg, 3),
      predicted_miss_distance_km: Float.round(predicted_miss, 2),
      pre_burn_orbit: get_orbital_elements(asset),
      post_burn_orbit: get_orbital_elements(asset),  # Returns to original orbit
      status: :proposed
    }
  end

  # TASK-331: Station keeping (no maneuver)
  @doc """
  Calculates a station keeping COA (accepting the risk).
  """
  def calculate_station_keeping(conjunction, _asset) do
    %{
      conjunction_id: conjunction.id,
      type: :station_keeping,
      name: "Station Keeping",
      objective: "Maintain current orbit and accept collision risk",
      description: "No maneuver performed. Continue monitoring conjunction and accept current collision probability.",
      delta_v_magnitude: 0.0,
      delta_v_direction: %{"x" => 0.0, "y" => 0.0, "z" => 0.0},
      burn_start_time: nil,
      burn_duration_seconds: 0.0,
      estimated_fuel_kg: 0.0,
      predicted_miss_distance_km: conjunction.miss_distance_km,
      pre_burn_orbit: nil,
      post_burn_orbit: nil,
      status: :proposed
    }
  end

  # TASK-332-335: Risk scoring algorithm
  defp add_risk_score(coa, conjunction, asset) do
    fuel_score = calculate_fuel_risk(coa, asset)
    time_score = calculate_time_risk(conjunction)
    improvement_score = calculate_improvement_risk(coa, conjunction)
    complexity_score = calculate_complexity_risk(coa)

    # TASK-336: Combined risk score (0-100)
    risk_score = (fuel_score * 0.3 + time_score * 0.25 +
                  improvement_score * 0.3 + complexity_score * 0.15)
                 |> Float.round(1)
                 |> max(0.0)
                 |> min(100.0)

    Map.put(coa, :risk_score, risk_score)
  end

  # TASK-333: Fuel risk component
  defp calculate_fuel_risk(coa, _asset) do
    fuel_used = coa.estimated_fuel_kg
    fuel_available = @default_fuel

    if fuel_available > 0 do
      (fuel_used / fuel_available) * 100
    else
      100.0
    end
  end

  # TASK-334: Time risk component
  defp calculate_time_risk(conjunction) do
    time_to_tca = DateTime.diff(conjunction.tca, DateTime.utc_now(), :second)

    cond do
      time_to_tca < 3600 -> 100.0     # < 1 hour - critical
      time_to_tca < 7200 -> 75.0      # < 2 hours - high
      time_to_tca < 14400 -> 50.0     # < 4 hours - medium
      time_to_tca < 43200 -> 25.0     # < 12 hours - low
      true -> 10.0                     # > 12 hours - minimal
    end
  end

  # TASK-335: Improvement risk (lower is better improvement)
  defp calculate_improvement_risk(coa, conjunction) do
    original_miss = conjunction.miss_distance_km
    predicted_miss = coa.predicted_miss_distance_km

    improvement = predicted_miss - original_miss

    cond do
      improvement >= 20.0 -> 0.0
      improvement >= 10.0 -> 20.0
      improvement >= 5.0 -> 40.0
      improvement >= 1.0 -> 60.0
      improvement > 0 -> 80.0
      true -> 100.0  # No improvement
    end
  end

  defp calculate_complexity_risk(coa) do
    case coa.type do
      :station_keeping -> 0.0
      :retrograde_burn -> 20.0
      :prograde_burn -> 20.0
      :phasing -> 50.0
      :inclination_change -> 80.0
      :flyby -> 100.0
      _ -> 50.0
    end
  end

  defp rank_by_risk(coas) do
    Enum.sort_by(coas, & &1.risk_score, :asc)
  end

  # Helper functions

  defp get_asset(asset_id) do
    case Satellites.get_satellite(asset_id) do
      nil -> {:error, :asset_not_found}
      asset -> {:ok, asset}
    end
  end

  defp get_altitude(asset) do
    # Extract altitude from position or use default
    case asset do
      %{position: %{x_km: x, y_km: y, z_km: z}} ->
        :math.sqrt(x * x + y * y + z * z) - @earth_radius
      _ ->
        400.0  # Default LEO altitude
    end
  end

  defp calculate_orbital_velocity(altitude) do
    r = @earth_radius + altitude
    :math.sqrt(@earth_mu / r)
  end

  defp calculate_orbital_period(altitude) do
    r = @earth_radius + altitude
    2 * :math.pi() * :math.sqrt(:math.pow(r, 3) / @earth_mu)
  end

  defp calculate_fuel_consumption(delta_v, mass, isp) do
    # Tsiolkovsky rocket equation: m0/mf = e^(Δv/(g0*Isp))
    g0 = 9.80665  # m/s²
    delta_v_m_s = delta_v * 1000  # Convert km/s to m/s

    mass_ratio = :math.exp(delta_v_m_s / (g0 * isp))
    fuel_mass = mass * (1 - 1 / mass_ratio)

    max(0.0, fuel_mass)
  end

  defp get_orbital_elements(_asset) do
    # Simplified - would calculate from state vectors in production
    %{
      "a" => @earth_radius + 400.0,  # Semi-major axis
      "e" => 0.0001,                  # Eccentricity
      "i" => 51.6,                    # Inclination (degrees)
      "raan" => 0.0,                  # Right ascension of ascending node
      "argp" => 0.0,                  # Argument of periapsis
      "ta" => 0.0                     # True anomaly
    }
  end

  defp calculate_post_burn_orbit(_asset, delta_v) do
    elements = get_orbital_elements(nil)

    # Simplified: adjust semi-major axis based on velocity change
    velocity_ratio = 1 + delta_v / calculate_orbital_velocity(400.0)
    new_a = elements["a"] * velocity_ratio * velocity_ratio

    Map.put(elements, "a", Float.round(new_a, 2))
  end
end
