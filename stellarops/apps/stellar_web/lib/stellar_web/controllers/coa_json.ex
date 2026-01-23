defmodule StellarWeb.COAJSON do
  @moduledoc """
  JSON rendering for COA endpoints.
  """

  alias StellarData.COAs.COA

  @doc """
  Renders a list of COAs.
  """
  def index(%{coas: coas}) do
    %{data: for(coa <- coas, do: data(coa))}
  end

  @doc """
  Renders a single COA with optional execution status.
  """
  def show(%{coa: coa, execution_status: execution_status}) do
    %{data: data(coa, execution_status)}
  end

  def show(%{coa: coa}) do
    %{data: data(coa)}
  end

  @doc """
  Renders a selected COA with its missions.
  """
  def select(%{coa: coa, missions: missions}) do
    %{
      data: data(coa),
      missions: Enum.map(missions, &mission_data/1)
    }
  end

  defp data(%COA{} = coa, execution_status \\ nil) do
    base = %{
      id: coa.id,
      coa_type: coa.coa_type,
      type: coa.type,
      priority: coa.priority,
      status: coa.status,
      title: coa.title,
      description: coa.description,
      rationale: coa.rationale,
      conjunction_id: coa.conjunction_id,
      satellite_id: coa.satellite_id,
      maneuver: %{
        time: coa.maneuver_time,
        burn_start_time: coa.burn_start_time,
        delta_v_ms: coa.delta_v_ms,
        delta_v_magnitude: coa.delta_v_magnitude,
        delta_v_direction: coa.delta_v_direction,
        delta_v_radial_ms: coa.delta_v_radial_ms,
        delta_v_in_track_ms: coa.delta_v_in_track_ms,
        delta_v_cross_track_ms: coa.delta_v_cross_track_ms,
        burn_duration_s: coa.burn_duration_s,
        burn_duration_seconds: coa.burn_duration_seconds,
        fuel_cost_kg: coa.fuel_cost_kg,
        estimated_fuel_kg: coa.estimated_fuel_kg
      },
      post_maneuver: %{
        miss_distance_m: coa.post_maneuver_miss_distance_m,
        predicted_miss_distance_km: coa.predicted_miss_distance_km,
        collision_probability: coa.post_maneuver_probability,
        new_orbit_apogee_km: coa.new_orbit_apogee_km,
        new_orbit_perigee_km: coa.new_orbit_perigee_km,
        pre_burn_orbit: coa.pre_burn_orbit,
        post_burn_orbit: coa.post_burn_orbit
      },
      scores: %{
        risk_if_no_action: coa.risk_if_no_action,
        risk_score: coa.risk_score,
        effectiveness: coa.effectiveness_score,
        mission_impact: coa.mission_impact_score,
        overall: coa.overall_score
      },
      decision: %{
        deadline: coa.decision_deadline,
        decided_by: coa.decided_by,
        decided_at: coa.decided_at,
        selected_by: coa.selected_by,
        selected_at: coa.selected_at,
        notes: coa.decision_notes
      },
      execution: %{
        command_id: coa.command_id,
        started_at: coa.execution_started_at,
        completed_at: coa.execution_completed_at,
        executed_at: coa.executed_at,
        result: coa.execution_result,
        failure_reason: coa.failure_reason
      },
      risks: coa.risks,
      assumptions: coa.assumptions,
      alternative_coa_ids: coa.alternative_coa_ids,
      inserted_at: coa.inserted_at,
      updated_at: coa.updated_at
    }

    # Include conjunction info if loaded
    base =
      if Ecto.assoc_loaded?(coa.conjunction) and coa.conjunction do
        Map.put(base, :conjunction, %{
          id: coa.conjunction.id,
          tca: coa.conjunction.tca,
          miss_distance_km: coa.conjunction.miss_distance_km,
          probability: coa.conjunction.probability
        })
      else
        base
      end

    # Include execution status if provided
    if execution_status do
      Map.put(base, :execution_status, execution_status)
    else
      base
    end
  end

  defp mission_data(mission) do
    %{
      id: mission.id,
      name: mission.name,
      type: mission.type,
      status: mission.status,
      priority: mission.priority,
      scheduled_start: mission.scheduled_start,
      estimated_duration_seconds: mission.estimated_duration_seconds
    }
  end
end
