defmodule StellarWeb.COAJSON do
  @moduledoc """
  JSON rendering for COA endpoints.
  """

  alias StellarData.COA.CourseOfAction

  @doc """
  Renders a list of COAs.
  """
  def index(%{coas: coas}) do
    %{data: for(coa <- coas, do: data(coa))}
  end

  @doc """
  Renders a single COA.
  """
  def show(%{coa: coa}) do
    %{data: data(coa)}
  end

  defp data(%CourseOfAction{} = coa) do
    %{
      id: coa.id,
      coa_type: coa.coa_type,
      priority: coa.priority,
      status: coa.status,
      title: coa.title,
      description: coa.description,
      rationale: coa.rationale,
      conjunction_id: coa.conjunction_id,
      satellite_id: coa.satellite_id,
      maneuver: %{
        time: coa.maneuver_time,
        delta_v_ms: coa.delta_v_ms,
        delta_v_radial_ms: coa.delta_v_radial_ms,
        delta_v_in_track_ms: coa.delta_v_in_track_ms,
        delta_v_cross_track_ms: coa.delta_v_cross_track_ms,
        burn_duration_s: coa.burn_duration_s,
        fuel_cost_kg: coa.fuel_cost_kg
      },
      post_maneuver: %{
        miss_distance_m: coa.post_maneuver_miss_distance_m,
        collision_probability: coa.post_maneuver_probability,
        new_orbit_apogee_km: coa.new_orbit_apogee_km,
        new_orbit_perigee_km: coa.new_orbit_perigee_km
      },
      scores: %{
        risk_if_no_action: coa.risk_if_no_action,
        effectiveness: coa.effectiveness_score,
        mission_impact: coa.mission_impact_score,
        overall: coa.overall_score
      },
      decision: %{
        deadline: coa.decision_deadline,
        decided_by: coa.decided_by,
        decided_at: coa.decided_at,
        notes: coa.decision_notes
      },
      execution: %{
        command_id: coa.command_id,
        started_at: coa.execution_started_at,
        completed_at: coa.execution_completed_at,
        result: coa.execution_result
      },
      risks: coa.risks,
      assumptions: coa.assumptions,
      alternative_coa_ids: coa.alternative_coa_ids,
      inserted_at: coa.inserted_at,
      updated_at: coa.updated_at
    }
  end
end
