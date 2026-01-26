defmodule StellarCore.SSA.COAPlanner do
  @moduledoc """
  GenServer for generating Course of Action recommendations.

  Analyzes conjunction events and generates appropriate COA recommendations
  based on miss distance, collision probability, and operational constraints.

  ## Features
  - Automatic COA generation for new conjunctions
  - Maneuver planning with delta-V optimization
  - Fuel cost estimation
  - Mission impact assessment
  - Alternative COA generation

  ## COA Types Generated
  - avoidance_maneuver: For high-risk conjunctions
  - monitor: For medium-risk events
  - alert: When human decision required
  - no_action: When risk is acceptable
  """

  use GenServer
  require Logger

  alias StellarCore.Orbital
  alias StellarData.COA
  alias StellarData.Conjunctions
  alias StellarData.Satellites

  # Thresholds for COA type selection
  @critical_pc_threshold 1.0e-4  # Pc > 1e-4 = critical
  @high_pc_threshold 1.0e-5     # Pc > 1e-5 = high
  @critical_miss_threshold 100   # < 100m = critical
  @high_miss_threshold 500       # < 500m = high
  @monitor_miss_threshold 2000   # < 2km = monitor

  # Planning parameters
  @maneuver_lead_time_hours 12   # Minimum hours before TCA to execute maneuver
  @max_delta_v_ms 10.0           # Maximum delta-V for avoidance (m/s)
  @fuel_density_kg_per_ms 0.05   # Rough fuel cost per m/s delta-V

  # Orbital mechanics constants
  @earth_radius_km 6378.137      # WGS84 equatorial radius
  @earth_mu 398600.4418          # Earth gravitational parameter (km³/s²)

  defstruct [
    :processing
  ]

  # Client API

  @doc """
  Starts the COA Planner.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Generates COAs for a conjunction.
  """
  def generate_coas(conjunction_id) do
    GenServer.call(__MODULE__, {:generate_coas, conjunction_id}, 30_000)
  end

  @doc """
  Generates COAs for all pending conjunctions.
  """
  def process_pending_conjunctions do
    GenServer.cast(__MODULE__, :process_pending)
  end

  @doc """
  Plans an avoidance maneuver for a specific conjunction.
  """
  def plan_maneuver(conjunction_id, opts \\ []) do
    GenServer.call(__MODULE__, {:plan_maneuver, conjunction_id, opts}, 30_000)
  end

  @doc """
  Evaluates the effectiveness of a proposed maneuver.
  """
  def evaluate_maneuver(satellite_id, maneuver_params) do
    GenServer.call(__MODULE__, {:evaluate_maneuver, satellite_id, maneuver_params}, 30_000)
  end

  @doc """
  Gets the current processing status.
  """
  def get_status do
    GenServer.call(__MODULE__, :get_status)
  end

  # Server Callbacks

  @impl true
  def init(_opts) do
    # Use handle_continue to defer subscription until after init completes
    # This ensures Phoenix.PubSub is fully available before subscribing
    {:ok, %__MODULE__{processing: false}, {:continue, :subscribe}}
  end

  @impl true
  def handle_continue(:subscribe, state) do
    # Subscribe to conjunction events
    Phoenix.PubSub.subscribe(StellarCore.PubSub, "ssa:conjunctions")
    Logger.info("[COAPlanner] Started and subscribed to ssa:conjunctions")
    {:noreply, state}
  end

  @impl true
  def handle_call(:get_status, _from, state) do
    {:reply, %{processing: state.processing}, state}
  end

  @impl true
  def handle_call({:generate_coas, conjunction_id}, _from, state) do
    result = do_generate_coas(conjunction_id)
    {:reply, result, state}
  end

  @impl true
  def handle_call({:plan_maneuver, conjunction_id, opts}, _from, state) do
    result = do_plan_maneuver(conjunction_id, opts)
    {:reply, result, state}
  end

  @impl true
  def handle_call({:evaluate_maneuver, satellite_id, params}, _from, state) do
    result = do_evaluate_maneuver(satellite_id, params)
    {:reply, result, state}
  end

  @impl true
  def handle_cast(:process_pending, state) do
    if state.processing do
      {:noreply, state}
    else
      spawn_process_pending()
      {:noreply, %{state | processing: true}}
    end
  end

  @impl true
  def handle_info({:conjunction_detected, conjunction}, state) do
    # Automatically generate COAs for new conjunctions
    if conjunction.severity in [:high, :critical] do
      Task.start(fn -> do_generate_coas(conjunction.id) end)
    end
    {:noreply, state}
  end

  @impl true
  def handle_info({:processing_complete, _count}, state) do
    {:noreply, %{state | processing: false}}
  end

  @impl true
  def handle_info(_msg, state) do
    {:noreply, state}
  end

  # Private Functions

  defp spawn_process_pending do
    parent = self()
    Task.start(fn ->
      count = process_all_pending()
      send(parent, {:processing_complete, count})
    end)
  end

  defp process_all_pending do
    # Get all critical/high conjunctions without COAs
    Conjunctions.list_critical_conjunctions()
    |> Enum.filter(&needs_coa?/1)
    |> Enum.map(&do_generate_coas(&1.id))
    |> length()
  end

  defp needs_coa?(conjunction) do
    case COA.list_coas_for_conjunction(conjunction.id) do
      [] -> true
      coas -> not Enum.any?(coas, &(&1.status in [:proposed, :approved]))
    end
  end

  defp do_generate_coas(conjunction_id) do
    case Conjunctions.get_conjunction(conjunction_id) do
      nil ->
        {:error, :conjunction_not_found}

      conjunction ->
        # Preload primary_object to get satellite_id
        conjunction = StellarData.Repo.preload(conjunction, [:primary_object, :satellite])
        coas = generate_coa_options(conjunction)
        Logger.debug("[COAPlanner] Generated #{length(coas)} COA options for conjunction #{conjunction_id}, severity: #{conjunction.severity}")
        
        results = Enum.map(coas, fn coa_attrs ->
          result = COA.create_coa(coa_attrs)
          case result do
            {:error, changeset} -> 
              Logger.warning("[COAPlanner] Failed to create COA: #{inspect(changeset.errors)}")
            _ -> :ok
          end
          result
        end)

        successful = Enum.filter(results, fn
          {:ok, _} -> true
          _ -> false
        end) |> Enum.map(fn {:ok, coa} -> coa end)

        # Update conjunction with best recommendation
        if best = Enum.max_by(successful, & &1.overall_score, fn -> nil end) do
          Conjunctions.assign_coa(conjunction, best.id)
        end

        # Broadcast COA generation
        Phoenix.PubSub.broadcast(
          StellarCore.PubSub,
          "ssa:coa",
          {:coas_generated, %{
            conjunction_id: conjunction_id,
            count: length(successful)
          }}
        )

        {:ok, successful}
    end
  end

  defp generate_coa_options(conjunction) do
    # Get satellite_id - check multiple sources
    satellite_id = conjunction.satellite_id || 
                   get_satellite_id_from_primary(conjunction)
    
    Logger.debug("[COAPlanner] Conjunction #{conjunction.id}: satellite_id=#{inspect(satellite_id)}, primary_object=#{inspect(conjunction.primary_object)}, severity=#{inspect(conjunction.severity)}")
    
    if is_nil(satellite_id) do
      Logger.warning("[COAPlanner] Cannot generate COAs: no satellite_id found for conjunction #{conjunction.id}. The primary object needs to be linked to a satellite.")
      []
    else
      generate_coas_for_satellite(conjunction, satellite_id)
    end
  end

  defp get_satellite_id_from_primary(conjunction) do
    # Try to get satellite from preloaded primary_object
    case conjunction.primary_object do
      %{satellite_id: sat_id} when not is_nil(sat_id) -> sat_id
      _ -> nil
    end
  end

  defp generate_coas_for_satellite(conjunction, satellite_id) do
    # Generate maneuver COAs only - no monitoring options
    cond do
      # Critical: Need avoidance maneuver
      conjunction.severity == :critical ->
        generate_maneuver_options(conjunction, satellite_id)

      # High: Maneuver recommended but not mandatory
      conjunction.severity == :high ->
        generate_maneuver_options(conjunction, satellite_id)

      # Medium or Low: Still generate maneuver options for operator consideration
      true ->
        generate_maneuver_options(conjunction, satellite_id)
    end
  end

  defp build_base_coa(conjunction, satellite_id) do
    hours_to_tca = DateTime.diff(conjunction.tca, DateTime.utc_now()) / 3600

    %{
      conjunction_id: conjunction.id,
      satellite_id: satellite_id,
      decision_deadline: calculate_decision_deadline(conjunction.tca)
    }
  end

  defp generate_maneuver_options(conjunction, satellite_id) do
    # Generate multiple maneuver options with different characteristics
    tca = conjunction.tca
    
    # Get current orbital parameters from primary object
    current_orbit = get_orbital_params(conjunction)

    # Option 1: Early maneuver (lower delta-V, more lead time)
    early_time = DateTime.add(tca, -24 * 3600, :second)  # 24h before TCA
    early_maneuver = calculate_maneuver(conjunction, early_time, :posigrade, current_orbit)

    # Option 2: Late maneuver (higher delta-V, less disruption)
    late_time = DateTime.add(tca, -@maneuver_lead_time_hours * 3600, :second)
    late_maneuver = calculate_maneuver(conjunction, late_time, :posigrade, current_orbit)

    # Option 3: Retrograde maneuver (different direction)
    retro_maneuver = calculate_maneuver(conjunction, early_time, :retrograde, current_orbit)

    [early_maneuver, late_maneuver, retro_maneuver]
    |> Enum.filter(& &1)  # Remove failed calculations
    |> Enum.map(fn maneuver ->
      %{
        conjunction_id: conjunction.id,
        satellite_id: satellite_id,
        coa_type: :avoidance_maneuver,
        priority: conjunction.severity || :medium,
        maneuver_time: maneuver.time,
        delta_v_ms: maneuver.delta_v,
        delta_v_in_track_ms: maneuver.delta_v_in_track,
        delta_v_cross_track_ms: maneuver.delta_v_cross_track,
        delta_v_radial_ms: maneuver.delta_v_radial,
        burn_duration_s: maneuver.burn_duration,
        fuel_cost_kg: maneuver.fuel_cost,
        post_maneuver_miss_distance_m: maneuver.new_miss_distance,
        post_maneuver_probability: maneuver.post_maneuver_probability,
        new_orbit_apogee_km: maneuver.new_apogee_km,
        new_orbit_perigee_km: maneuver.new_perigee_km,
        risk_if_no_action: 0.8,
        effectiveness_score: maneuver.effectiveness,
        mission_impact_score: maneuver.mission_impact,
        title: maneuver.title,
        description: maneuver.description,
        rationale: maneuver.rationale,
        decision_deadline: calculate_decision_deadline(conjunction.tca)
      }
    end)
  end

  # Extract orbital parameters from conjunction's primary object
  defp get_orbital_params(conjunction) do
    case conjunction.primary_object do
      %{semi_major_axis_km: sma, eccentricity: ecc} when not is_nil(sma) ->
        %{
          semi_major_axis_km: sma,
          eccentricity: ecc || 0.001,
          apogee_km: conjunction.primary_object.apogee_km || calculate_apogee(sma, ecc || 0.001),
          perigee_km: conjunction.primary_object.perigee_km || calculate_perigee(sma, ecc || 0.001)
        }
      %{apogee_km: apogee, perigee_km: perigee} when not is_nil(apogee) and not is_nil(perigee) ->
        sma = (apogee + perigee + 2 * @earth_radius_km) / 2
        ecc = (apogee - perigee) / (apogee + perigee + 2 * @earth_radius_km)
        %{
          semi_major_axis_km: sma,
          eccentricity: ecc,
          apogee_km: apogee,
          perigee_km: perigee
        }
      _ ->
        # Default to typical LEO orbit if no data available
        %{
          semi_major_axis_km: 6778.0,  # ~400 km altitude
          eccentricity: 0.001,
          apogee_km: 400.0,
          perigee_km: 400.0
        }
    end
  end

  defp calculate_maneuver(conjunction, maneuver_time, direction, current_orbit) do
    # This is a simplified maneuver calculation
    # In production, this would call the Orbital service for precise calculations

    miss_distance = conjunction.miss_distance_m || 1000.0
    relative_velocity = conjunction.relative_velocity_ms || 100.0

    # Simple delta-V estimation based on miss distance needed
    # Targeting 5x the miss distance to ensure safe separation
    target_separation = max(5000.0, miss_distance * 5.0)  # At least 5km
    
    # Time before TCA
    time_before_tca = DateTime.diff(conjunction.tca, maneuver_time)
    
    # Rough delta-V calculation: separation / time = velocity change needed
    # This is very simplified - real calculations would use orbital mechanics
    base_delta_v = min(target_separation / time_before_tca, @max_delta_v_ms)

    # Adjust based on direction
    {delta_v_in_track, delta_v_cross, delta_v_radial, title, desc} = case direction do
      :posigrade ->
        {base_delta_v * 0.8, base_delta_v * 0.2, 0.0,
         "Posigrade maneuver at #{format_time(maneuver_time)}",
         "In-track velocity increase to raise orbit ahead of conjunction."}
      :retrograde ->
        {-base_delta_v * 0.8, base_delta_v * 0.2, 0.0,
         "Retrograde maneuver at #{format_time(maneuver_time)}",
         "In-track velocity decrease to lower orbit before conjunction."}
      :cross_track ->
        {0.0, base_delta_v, 0.0,
         "Cross-track maneuver at #{format_time(maneuver_time)}",
         "Out-of-plane maneuver to change orbital plane."}
    end

    total_delta_v = :math.sqrt(
      delta_v_in_track * delta_v_in_track +
      delta_v_cross * delta_v_cross +
      delta_v_radial * delta_v_radial
    )

    fuel_cost = total_delta_v * @fuel_density_kg_per_ms

    # Estimate new miss distance (simplified)
    new_miss_distance = target_separation

    # Calculate new orbital parameters after the burn
    {new_apogee_km, new_perigee_km} = calculate_new_orbit(current_orbit, delta_v_in_track)
    
    # Estimate post-maneuver collision probability
    # Using simplified probability model: Pc ∝ exp(-miss_distance² / (2 * σ²))
    # Where σ is the combined position uncertainty (typically ~100m for well-tracked objects)
    post_maneuver_probability = estimate_collision_probability(
      new_miss_distance,
      relative_velocity,
      conjunction.collision_probability
    )

    # Calculate scores
    effectiveness = min(1.0, new_miss_distance / 5000)  # 5km = 100% effective
    mission_impact = min(1.0, fuel_cost / 10.0)  # 10kg = 100% impact

    %{
      time: maneuver_time,
      delta_v: Float.round(total_delta_v, 3),
      delta_v_in_track: Float.round(delta_v_in_track, 3),
      delta_v_cross_track: Float.round(delta_v_cross, 3),
      delta_v_radial: Float.round(delta_v_radial, 3),
      burn_duration: Float.round(total_delta_v * 10, 1),  # Rough estimate
      fuel_cost: Float.round(fuel_cost, 3),
      new_miss_distance: Float.round(new_miss_distance, 1),
      new_apogee_km: Float.round(new_apogee_km, 2),
      new_perigee_km: Float.round(new_perigee_km, 2),
      post_maneuver_probability: post_maneuver_probability,
      effectiveness: Float.round(effectiveness, 3),
      mission_impact: Float.round(mission_impact, 3),
      title: title,
      description: desc,
      rationale: "Maneuver designed to increase separation to #{round(new_miss_distance)}m by TCA."
    }
  end

  # Calculate new apogee/perigee after an in-track delta-V burn
  # Using vis-viva equation and simplified orbital mechanics
  defp calculate_new_orbit(current_orbit, delta_v_in_track_ms) do
    # Current orbital parameters
    sma = current_orbit.semi_major_axis_km
    ecc = current_orbit.eccentricity
    
    # Current velocity at periapsis (km/s) using vis-viva: v² = μ(2/r - 1/a)
    r_periapsis = sma * (1 - ecc)
    v_periapsis = :math.sqrt(@earth_mu * (2.0 / r_periapsis - 1.0 / sma))
    
    # Apply delta-V (convert m/s to km/s)
    delta_v_km_s = delta_v_in_track_ms / 1000.0
    new_v = v_periapsis + delta_v_km_s
    
    # New semi-major axis from vis-viva: 1/a = 2/r - v²/μ
    new_sma = 1.0 / (2.0 / r_periapsis - (new_v * new_v) / @earth_mu)
    
    # For small burns, periapsis stays roughly the same
    new_r_periapsis = r_periapsis
    
    # Calculate new apoapsis from semi-major axis
    new_r_apoapsis = 2 * new_sma - new_r_periapsis
    
    # Convert to altitudes (subtract Earth radius)
    new_apogee_km = new_r_apoapsis - @earth_radius_km
    new_perigee_km = new_r_periapsis - @earth_radius_km
    
    # Ensure non-negative altitudes
    {max(0.0, new_apogee_km), max(0.0, new_perigee_km)}
  end

  # Estimate post-maneuver collision probability using a simplified model
  # Based on the hard-body radius approach with Gaussian position uncertainties
  defp estimate_collision_probability(new_miss_distance_m, relative_velocity_ms, original_probability) do
    # Combined position uncertainty (1-sigma) in meters
    # Typical values: 50-200m for well-tracked objects
    sigma = 100.0
    
    # Hard-body radius (combined radii of both objects) in meters
    # Typical satellite: 1-5m, debris: 0.1-1m
    hard_body_radius = 5.0
    
    # Probability using simplified 2D Gaussian model
    # Pc ≈ (π * r² / (2π * σ²)) * exp(-d² / (2σ²))
    # Simplified to: Pc ≈ (r/σ)² * exp(-d² / (2σ²))
    
    if new_miss_distance_m <= 0 do
      1.0
    else
      exponent = -(new_miss_distance_m * new_miss_distance_m) / (2.0 * sigma * sigma)
      probability = (hard_body_radius / sigma) * (hard_body_radius / sigma) * :math.exp(exponent)
      
      # Cap at original probability and ensure it's reduced significantly
      min_reduction = 0.01  # At least 100x reduction expected
      max_probability = (original_probability || 0.001) * min_reduction
      
      Float.round(min(probability, max_probability), 10)
    end
  end

  defp calculate_apogee(sma, ecc), do: sma * (1 + ecc) - @earth_radius_km
  defp calculate_perigee(sma, ecc), do: sma * (1 - ecc) - @earth_radius_km

  defp do_plan_maneuver(conjunction_id, opts) do
    case Conjunctions.get_conjunction(conjunction_id) do
      nil ->
        {:error, :conjunction_not_found}

      conjunction ->
        conjunction = StellarData.Repo.preload(conjunction, [:primary_object])
        current_orbit = get_orbital_params(conjunction)
        lead_hours = Keyword.get(opts, :lead_hours, 24)
        direction = Keyword.get(opts, :direction, :posigrade)
        
        maneuver_time = DateTime.add(conjunction.tca, -lead_hours * 3600, :second)
        maneuver = calculate_maneuver(conjunction, maneuver_time, direction, current_orbit)

        {:ok, maneuver}
    end
  end

  defp do_evaluate_maneuver(satellite_id, params) do
    # Evaluate the impact of a proposed maneuver
    case Satellites.get_satellite(satellite_id) do
      nil ->
        {:error, :satellite_not_found}

      satellite ->
        delta_v = Map.get(params, :delta_v_ms, 0)
        fuel_cost = delta_v * @fuel_density_kg_per_ms

        evaluation = %{
          satellite_id: satellite_id,
          delta_v_ms: delta_v,
          estimated_fuel_cost_kg: Float.round(fuel_cost, 3),
          feasible: delta_v <= @max_delta_v_ms,
          warnings: generate_warnings(satellite, delta_v, fuel_cost)
        }

        {:ok, evaluation}
    end
  end

  defp generate_warnings(_satellite, delta_v, _fuel_cost) do
    warnings = []

    warnings = if delta_v > @max_delta_v_ms * 0.8 do
      ["Large delta-V may exceed thruster capabilities" | warnings]
    else
      warnings
    end

    warnings = if delta_v > @max_delta_v_ms * 0.5 do
      ["Significant fuel expenditure required" | warnings]
    else
      warnings
    end

    warnings
  end

  defp calculate_risk_score(conjunction) do
    pc = conjunction.collision_probability || 0
    miss_distance = conjunction.miss_distance_m || 10_000

    pc_score = cond do
      pc > @critical_pc_threshold -> 0.95
      pc > @high_pc_threshold -> 0.75
      pc > 1.0e-6 -> 0.5
      true -> 0.2
    end

    distance_score = cond do
      miss_distance < @critical_miss_threshold -> 0.95
      miss_distance < @high_miss_threshold -> 0.75
      miss_distance < @monitor_miss_threshold -> 0.5
      true -> 0.2
    end

    # Take the maximum risk
    max(pc_score, distance_score)
  end

  defp calculate_decision_deadline(tca) do
    # Decision needed at least 6 hours before maneuver
    # Maneuver at least 12 hours before TCA
    # So decision deadline is 18 hours before TCA
    DateTime.add(tca, -18 * 3600, :second)
  end

  defp format_time(datetime) do
    Calendar.strftime(datetime, "%Y-%m-%d %H:%M UTC")
  end
end
