defmodule StellarWeb.ConjunctionJSON do
  @moduledoc """
  JSON rendering for conjunction endpoints.
  """

  alias StellarData.Conjunctions.Conjunction

  @doc """
  Renders a list of conjunctions.
  """
  def index(%{conjunctions: conjunctions}) do
    %{data: for(conjunction <- conjunctions, do: data(conjunction))}
  end

  @doc """
  Renders a single conjunction.
  """
  def show(%{conjunction: conjunction}) do
    %{data: data(conjunction)}
  end

  defp data(%Conjunction{} = conjunction) do
    %{
      id: conjunction.id,
      tca: conjunction.tca,
      tca_uncertainty_seconds: conjunction.tca_uncertainty_seconds,
      miss_distance: %{
        total_m: conjunction.miss_distance_m,
        radial_m: conjunction.miss_distance_radial_m,
        in_track_m: conjunction.miss_distance_in_track_m,
        cross_track_m: conjunction.miss_distance_cross_track_m,
        uncertainty_m: conjunction.miss_distance_uncertainty_m
      },
      relative_velocity_ms: conjunction.relative_velocity_ms,
      collision_probability: conjunction.collision_probability,
      pc_method: conjunction.pc_method,
      severity: conjunction.severity,
      status: conjunction.status,
      primary_object: render_object(conjunction.primary_object),
      secondary_object: render_object(conjunction.secondary_object),
      satellite_id: conjunction.satellite_id,
      recommended_coa_id: conjunction.recommended_coa_id,
      executed_maneuver_id: conjunction.executed_maneuver_id,
      data_source: conjunction.data_source,
      cdm_id: conjunction.cdm_id,
      screening_date: conjunction.screening_date,
      last_updated: conjunction.last_updated,
      notes: conjunction.notes,
      inserted_at: conjunction.inserted_at,
      updated_at: conjunction.updated_at
    }
  end

  defp render_object(nil), do: nil
  defp render_object(%Ecto.Association.NotLoaded{}), do: nil
  defp render_object(object) do
    %{
      id: object.id,
      norad_id: object.norad_id,
      name: object.name,
      object_type: object.object_type,
      owner: object.owner,
      threat_level: object.threat_level
    }
  end
end
