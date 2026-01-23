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
      asset_id: conjunction.asset_id,
      object_id: conjunction.object_id,
      object: object_data(conjunction.object),
      tca: conjunction.tca,
      miss_distance_km: conjunction.miss_distance_km,
      relative_velocity_km_s: conjunction.relative_velocity_km_s,
      probability_of_collision: conjunction.probability_of_collision,
      severity: conjunction.severity,
      status: conjunction.status,
      asset_position_at_tca: conjunction.asset_position_at_tca,
      object_position_at_tca: conjunction.object_position_at_tca,
      covariance_data: conjunction.covariance_data,
      inserted_at: conjunction.inserted_at,
      updated_at: conjunction.updated_at
    }

    # Add asset details if provided
    base =
      if asset_details do
        Map.put(base, :asset, asset_details)
      else
        base
      end

    # Add threat assessment if object is preloaded and has one
    base
    |> maybe_add_threat_assessment(conjunction.object)
  end

  defp object_data(nil), do: nil
  defp object_data(%Ecto.Association.NotLoaded{}), do: nil
  defp object_data(object) do
    %{
      id: object.id,
      norad_id: object.norad_id,
      name: object.name,
      object_type: object.object_type,
      orbital_status: object.orbital_status,
      owner: object.owner,
      tle_epoch: object.tle_epoch
    }
  end

  defp maybe_add_threat_assessment(data, nil), do: data
  defp maybe_add_threat_assessment(data, %Ecto.Association.NotLoaded{}), do: data
  defp maybe_add_threat_assessment(data, object) do
    # Try to load threat assessment
    case StellarData.Threats.get_assessment_by_object_id(object.id) do
      nil ->
        data

      assessment ->
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
