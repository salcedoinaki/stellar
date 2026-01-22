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
    # Subscribe to conjunction events
    Phoenix.PubSub.subscribe(StellarCore.PubSub, "ssa:conjunctions")

    Logger.info("[COAPlanner] Started")
    {:ok, %__MODULE__{processing: false}}
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
        coas = generate_coa_options(conjunction)
        
        results = Enum.map(coas, fn coa_attrs ->
          COA.create_coa(coa_attrs)
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
    satellite_id = conjunction.satellite_id
    
    coas = []

    # Always generate a "monitor" or "no_action" option
    base_coa = build_base_coa(conjunction, satellite_id)

    coas = cond do
      # Critical: Need avoidance maneuver
      conjunction.severity == :critical ->
        maneuver_coas = generate_maneuver_options(conjunction)
        monitor = Map.merge(base_coa, %{
          coa_type: :monitor,
          title: "Continue monitoring",
          description: "Monitor conjunction without maneuver. HIGH RISK.",
          risk_if_no_action: 0.9,
          effectiveness_score: 0.1,
          mission_impact_score: 0.0,
          priority: :critical
        })
        maneuver_coas ++ [monitor]

      # High: Maneuver recommended but not mandatory
      conjunction.severity == :high ->
        maneuver_coas = generate_maneuver_options(conjunction)
        monitor = Map.merge(base_coa, %{
          coa_type: :monitor,
          title: "Enhanced monitoring",
          description: "Increase tracking frequency and prepare contingency maneuver.",
          risk_if_no_action: 0.6,
          effectiveness_score: 0.5,
          mission_impact_score: 0.1,
          priority: :high
        })
        maneuver_coas ++ [monitor]

      # Medium: Monitor with alert
      conjunction.severity == :medium ->
        [
          Map.merge(base_coa, %{
            coa_type: :monitor,
            title: "Standard monitoring",
            description: "Continue tracking and update predictions.",
            risk_if_no_action: 0.3,
            effectiveness_score: 0.7,
            mission_impact_score: 0.0,
            priority: :medium
          }),
          Map.merge(base_coa, %{
            coa_type: :alert,
            title: "Operator alert",
            description: "Notify operators for situational awareness.",
            risk_if_no_action: 0.3,
            effectiveness_score: 0.6,
            mission_impact_score: 0.0,
            priority: :low
          })
        ]

      # Low: No action needed
      true ->
        [
          Map.merge(base_coa, %{
            coa_type: :no_action,
            title: "No action required",
            description: "Conjunction is within acceptable risk parameters.",
            risk_if_no_action: 0.1,
            effectiveness_score: 0.9,
            mission_impact_score: 0.0,
            priority: :low
          })
        ]
    end

    coas
  end

  defp build_base_coa(conjunction, satellite_id) do
    hours_to_tca = DateTime.diff(conjunction.tca, DateTime.utc_now()) / 3600

    %{
      conjunction_id: conjunction.id,
      satellite_id: satellite_id,
      decision_deadline: calculate_decision_deadline(conjunction.tca)
    }
  end

  defp generate_maneuver_options(conjunction) do
    # Generate multiple maneuver options with different characteristics
    tca = conjunction.tca
    satellite_id = conjunction.satellite_id

    # Option 1: Early maneuver (lower delta-V, more lead time)
    early_time = DateTime.add(tca, -24 * 3600, :second)  # 24h before TCA
    early_maneuver = calculate_maneuver(conjunction, early_time, :posigrade)

    # Option 2: Late maneuver (higher delta-V, less disruption)
    late_time = DateTime.add(tca, -@maneuver_lead_time_hours * 3600, :second)
    late_maneuver = calculate_maneuver(conjunction, late_time, :posigrade)

    # Option 3: Retrograde maneuver (different direction)
    retro_maneuver = calculate_maneuver(conjunction, early_time, :retrograde)

    [early_maneuver, late_maneuver, retro_maneuver]
    |> Enum.filter(& &1)  # Remove failed calculations
    |> Enum.map(fn maneuver ->
      %{
        conjunction_id: conjunction.id,
        satellite_id: satellite_id,
        coa_type: :avoidance_maneuver,
        priority: conjunction.severity,
        maneuver_time: maneuver.time,
        delta_v_ms: maneuver.delta_v,
        delta_v_in_track_ms: maneuver.delta_v_in_track,
        delta_v_cross_track_ms: maneuver.delta_v_cross_track,
        delta_v_radial_ms: maneuver.delta_v_radial,
        burn_duration_s: maneuver.burn_duration,
        fuel_cost_kg: maneuver.fuel_cost,
        post_maneuver_miss_distance_m: maneuver.new_miss_distance,
        risk_if_no_action: calculate_risk_score(conjunction),
        effectiveness_score: maneuver.effectiveness,
        mission_impact_score: maneuver.mission_impact,
        title: maneuver.title,
        description: maneuver.description,
        rationale: maneuver.rationale,
        decision_deadline: calculate_decision_deadline(conjunction.tca)
      }
    end)
  end

  defp calculate_maneuver(conjunction, maneuver_time, direction) do
    # This is a simplified maneuver calculation
    # In production, this would call the Orbital service for precise calculations

    miss_distance = conjunction.miss_distance_m || 1000
    relative_velocity = conjunction.relative_velocity_ms || 100

    # Simple delta-V estimation based on miss distance needed
    # Targeting 5x the miss distance to ensure safe separation
    target_separation = max(5000, miss_distance * 5)  # At least 5km
    
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
      effectiveness: Float.round(effectiveness, 3),
      mission_impact: Float.round(mission_impact, 3),
      title: title,
      description: desc,
      rationale: "Maneuver designed to increase separation to #{round(new_miss_distance)}m by TCA."
    }
  end

  defp do_plan_maneuver(conjunction_id, opts) do
    case Conjunctions.get_conjunction(conjunction_id) do
      nil ->
        {:error, :conjunction_not_found}

      conjunction ->
        lead_hours = Keyword.get(opts, :lead_hours, 24)
        direction = Keyword.get(opts, :direction, :posigrade)
        
        maneuver_time = DateTime.add(conjunction.tca, -lead_hours * 3600, :second)
        maneuver = calculate_maneuver(conjunction, maneuver_time, direction)

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
