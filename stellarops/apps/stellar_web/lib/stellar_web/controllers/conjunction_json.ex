defmodule StellarWeb.ConjunctionJSON do
  @moduledoc """
  JSON rendering for conjunction endpoints.
  """

  alias StellarData.Conjunctions.Conjunction

  @doc """
  Renders a list of conjunctions.
  """
  def index(%{conjunctions: conjunctions}) do
    %{data: for(conjunction <- conjunctions, do: data(conjunction, nil))}
  end

  @doc """
  Renders a single conjunction.
  """
  def show(%{conjunction: conjunction, asset_details: asset_details}) do
    %{data: data(conjunction, asset_details)}
  end

  def show(%{conjunction: conjunction}) do
    %{data: data(conjunction, nil)}
  end

  defp data(%Conjunction{} = conjunction, asset_details) do
    base = %{
      id: conjunction.id,
      satellite_id: conjunction.satellite_id,
      primary_object_id: conjunction.primary_object_id,
      secondary_object_id: conjunction.secondary_object_id,
      primary_object: object_data(conjunction.primary_object),
      secondary_object: object_data(conjunction.secondary_object),
      tca: conjunction.tca,
      tca_uncertainty_seconds: conjunction.tca_uncertainty_seconds,
      miss_distance_m: conjunction.miss_distance_m,
      miss_distance_radial_m: conjunction.miss_distance_radial_m,
      miss_distance_in_track_m: conjunction.miss_distance_in_track_m,
      miss_distance_cross_track_m: conjunction.miss_distance_cross_track_m,
      relative_velocity_ms: conjunction.relative_velocity_ms,
      collision_probability: conjunction.collision_probability,
      severity: conjunction.severity,
      status: conjunction.status,
      data_source: conjunction.data_source,
      cdm_id: conjunction.cdm_id,
      notes: conjunction.notes,
      inserted_at: conjunction.inserted_at,
      updated_at: conjunction.updated_at
    }

    # Add asset details if provided
    if asset_details do
      Map.put(base, :asset, asset_details)
    else
      base
    end
  end

  defp object_data(nil), do: nil
  defp object_data(%Ecto.Association.NotLoaded{}), do: nil
  defp object_data(object) do
    %{
      id: object.id,
      norad_id: object.norad_id,
      name: object.name,
      object_type: object.object_type,
      status: object.status,
      owner: object.owner,
      threat_level: object.threat_level,
      orbit_type: object.orbit_type
    }
  end
end
        Map.put(data, :threat_assessment, %{
          classification: assessment.classification,
          threat_level: assessment.threat_level,
          capabilities: assessment.capabilities,
          confidence_level: assessment.confidence_level,
          intel_summary: assessment.intel_summary
        })
    end
  end
end
