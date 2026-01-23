defmodule StellarWeb.COAJSON do
  @moduledoc """
  JSON rendering for COA resources.
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
      type: coa.type,
      delta_v_magnitude: coa.delta_v_magnitude,
      delta_v_direction: coa.delta_v_direction,
      burn_start_time: coa.burn_start_time,
      burn_duration_seconds: coa.burn_duration_seconds,
      risk_score: coa.risk_score,
      status: coa.status,
      estimated_fuel_kg: coa.estimated_fuel_kg,
      predicted_miss_distance_km: coa.predicted_miss_distance_km,
      pre_burn_orbit: coa.pre_burn_orbit,
      post_burn_orbit: coa.post_burn_orbit,
      selected_at: coa.selected_at,
      selected_by: coa.selected_by,
      executed_at: coa.executed_at,
      failure_reason: coa.failure_reason,
      inserted_at: coa.inserted_at,
      updated_at: coa.updated_at
    }

    # Include conjunction info if loaded
    base = if Ecto.assoc_loaded?(coa.conjunction) and coa.conjunction do
      Map.put(base, :conjunction, %{
        id: coa.conjunction.id,
        tca: coa.conjunction.tca,
        miss_distance_km: coa.conjunction.miss_distance_km,
        probability: coa.conjunction.probability
      })
    else
      Map.put(base, :conjunction_id, coa.conjunction_id)
    end

    # Include execution status if provided
    if execution_status do
      Map.put(base, :execution, execution_status)
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
