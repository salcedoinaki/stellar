defmodule StellarCore.COAExecutor do
  @moduledoc """
  COA Execution service.

  Converts selected COAs into executable missions and monitors
  their execution status.
  """

  require Logger

  alias StellarData.COAs
  alias StellarData.COAs.COA
  alias StellarData.Missions
  alias StellarCore.Alarms

  # TASK-343: Execute a COA
  @doc """
  Executes a selected COA by creating the required missions.

  This creates:
  1. Pre-burn preparation mission
  2. Main burn execution mission
  3. Post-burn verification mission
  """
  def execute_coa(%COA{status: :selected} = coa) do
    with {:ok, coa} <- COAs.execute_coa(coa),
         {:ok, missions} <- create_missions_for_coa(coa) do

      Logger.info("COA execution started",
        coa_id: coa.id,
        coa_type: coa.type,
        mission_count: length(missions)
      )

      # Publish event
      Phoenix.PubSub.broadcast(
        StellarWeb.PubSub,
        "coa:updates",
        {:coa_executing, coa.id}
      )

      {:ok, %{coa: coa, missions: missions}}
    else
      {:error, reason} ->
        Logger.error("COA execution failed", coa_id: coa.id, reason: inspect(reason))
        {:error, reason}
    end
  end

  def execute_coa(%COA{} = _coa), do: {:error, :coa_not_selected}

  # TASK-344-346: Create missions for COA
  defp create_missions_for_coa(coa) do
    conjunction = StellarData.Conjunctions.get_conjunction(coa.conjunction_id)

    if conjunction do
      missions = create_mission_sequence(coa, conjunction)
      {:ok, missions}
    else
      {:error, :conjunction_not_found}
    end
  end

  defp create_mission_sequence(coa, conjunction) do
    # Skip station keeping - no missions needed
    if coa.type == :station_keeping do
      []
    else
      [
        create_pre_burn_mission(coa, conjunction),
        create_main_burn_mission(coa, conjunction),
        create_post_burn_mission(coa, conjunction)
      ]
      |> Enum.filter(&match?({:ok, _}, &1))
      |> Enum.map(fn {:ok, mission} -> mission end)
    end
  end

  # TASK-344: Pre-burn preparation mission
  defp create_pre_burn_mission(coa, conjunction) do
    # Start preparation 30 minutes before burn
    prep_start = DateTime.add(coa.burn_start_time, -1800, :second)

    mission_attrs = %{
      satellite_id: conjunction.asset_id,
      coa_id: coa.id,
      name: "Pre-Burn Preparation: #{coa.name}",
      type: :maneuver_prep,
      status: :pending,
      priority: :high,
      parameters: %{
        "phase" => "preparation",
        "target_delta_v" => coa.delta_v_magnitude,
        "burn_direction" => coa.delta_v_direction
      },
      scheduled_start: prep_start,
      deadline: coa.burn_start_time,
      required_energy: 10.0,
      required_memory: 5.0,
      required_bandwidth: 0.0
    }

    create_mission(mission_attrs)
  end

  # TASK-345: Main burn execution mission
  defp create_main_burn_mission(coa, conjunction) do
    mission_attrs = %{
      satellite_id: conjunction.asset_id,
      coa_id: coa.id,
      name: "Execute Burn: #{coa.name}",
      type: :maneuver_execute,
      status: :pending,
      priority: :critical,
      parameters: %{
        "phase" => "execution",
        "delta_v_magnitude" => coa.delta_v_magnitude,
        "delta_v_direction" => coa.delta_v_direction,
        "burn_duration_seconds" => coa.burn_duration_seconds,
        "fuel_estimate_kg" => coa.estimated_fuel_kg
      },
      scheduled_start: coa.burn_start_time,
      deadline: DateTime.add(coa.burn_start_time, round(coa.burn_duration_seconds) + 300, :second),
      required_energy: 30.0,
      required_memory: 10.0,
      required_bandwidth: 0.0
    }

    create_mission(mission_attrs)
  end

  # TASK-346: Post-burn verification mission
  defp create_post_burn_mission(coa, conjunction) do
    # Start verification after burn completes
    verify_start = DateTime.add(coa.burn_start_time, round(coa.burn_duration_seconds) + 60, :second)

    mission_attrs = %{
      satellite_id: conjunction.asset_id,
      coa_id: coa.id,
      name: "Post-Burn Verification: #{coa.name}",
      type: :maneuver_verify,
      status: :pending,
      priority: :high,
      parameters: %{
        "phase" => "verification",
        "expected_orbit" => coa.post_burn_orbit,
        "expected_miss_distance" => coa.predicted_miss_distance_km
      },
      scheduled_start: verify_start,
      deadline: DateTime.add(verify_start, 3600, :second),
      required_energy: 15.0,
      required_memory: 10.0,
      required_bandwidth: 1.0  # Need downlink for verification data
    }

    create_mission(mission_attrs)
  end

  defp create_mission(attrs) do
    case Missions.create_mission(attrs) do
      {:ok, mission} ->
        Logger.debug("Created mission for COA", mission_id: mission.id, type: attrs.type)
        {:ok, mission}

      {:error, changeset} ->
        Logger.error("Failed to create mission", error: inspect(changeset))
        {:error, changeset}
    end
  end

  # TASK-348-350: Status transition handlers
  @doc """
  Handles mission completion and updates COA status accordingly.
  """
  def handle_mission_complete(mission) do
    case mission.type do
      :maneuver_verify ->
        # All phases complete
        complete_coa_execution(mission.coa_id)

      _ ->
        # Intermediate mission, continue execution
        {:ok, :continuing}
    end
  end

  @doc """
  Handles mission failure and updates COA status.
  """
  def handle_mission_failure(mission, reason) do
    coa = COAs.get_coa(mission.coa_id)

    if coa do
      # TASK-350: Mark COA as failed
      {:ok, _failed_coa} = COAs.fail_coa(coa, reason)

      # TASK-354: Raise alarm
      Alarms.raise_alarm(
        :coa_execution_failed,
        "COA execution failed: #{coa.name}",
        :major,
        %{coa_id: coa.id, mission_id: mission.id, reason: reason}
      )

      # Notify via PubSub
      Phoenix.PubSub.broadcast(
        StellarWeb.PubSub,
        "coa:updates",
        {:coa_failed, coa.id, reason}
      )

      {:ok, :failed}
    else
      {:error, :coa_not_found}
    end
  end

  # TASK-349: Complete COA execution
  defp complete_coa_execution(coa_id) do
    coa = COAs.get_coa(coa_id)

    if coa do
      {:ok, completed_coa} = COAs.complete_coa(coa)

      # TASK-351-352: Verify post-burn orbit
      verify_post_burn_orbit(completed_coa)

      Logger.info("COA execution completed", coa_id: coa_id)

      Phoenix.PubSub.broadcast(
        StellarWeb.PubSub,
        "coa:updates",
        {:coa_completed, coa_id}
      )

      {:ok, completed_coa}
    else
      {:error, :coa_not_found}
    end
  end

  # TASK-351-353: Post-burn orbit verification
  defp verify_post_burn_orbit(coa) do
    # In production, this would compare actual orbital elements from tracking
    # with predicted elements from the COA

    expected_orbit = coa.post_burn_orbit

    # Simulated actual orbit (would come from tracking in production)
    actual_orbit = simulate_actual_orbit(expected_orbit)

    deviation = calculate_orbit_deviation(expected_orbit, actual_orbit)

    # TASK-353: Generate correction burn if deviation is too large
    if deviation > 0.01 do  # 1% deviation threshold
      Logger.warning("Post-burn orbit deviation detected",
        coa_id: coa.id,
        deviation_percent: deviation * 100
      )

      # Would generate correction COA here
      {:deviation_detected, deviation}
    else
      {:ok, :orbit_verified}
    end
  end

  defp simulate_actual_orbit(expected_orbit) when is_map(expected_orbit) do
    # Add small random deviation for simulation
    Map.new(expected_orbit, fn {key, value} when is_number(value) ->
      {key, value * (1 + (:rand.uniform() - 0.5) * 0.002)}
    end)
  end

  defp simulate_actual_orbit(_), do: nil

  defp calculate_orbit_deviation(expected, actual) when is_map(expected) and is_map(actual) do
    # Calculate RMS deviation across orbital elements
    deviations = Enum.map(["a", "e", "i"], fn key ->
      exp_val = Map.get(expected, key, 0)
      act_val = Map.get(actual, key, 0)

      if exp_val != 0 do
        abs((act_val - exp_val) / exp_val)
      else
        0
      end
    end)

    Enum.sum(deviations) / length(deviations)
  end

  defp calculate_orbit_deviation(_, _), do: 0

  @doc """
  Gets execution status for a COA including linked missions.
  """
  def get_execution_status(coa_id) do
    coa = COAs.get_coa(coa_id)

    if coa do
      missions = Missions.list_missions_for_coa(coa_id)

      mission_status = %{
        total: length(missions),
        completed: Enum.count(missions, &(&1.status == :completed)),
        failed: Enum.count(missions, &(&1.status == :failed)),
        pending: Enum.count(missions, &(&1.status in [:pending, :scheduled, :running]))
      }

      %{
        coa: coa,
        missions: missions,
        mission_status: mission_status,
        progress: if(mission_status.total > 0,
          do: mission_status.completed / mission_status.total * 100,
          else: 0
        )
      }
    else
      nil
    end
  end
end
