defmodule StellarWeb.ConjunctionJSON do
  @moduledoc """
  JSON rendering for conjunctions.
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
  end

  defp object_data(nil), do: nil
  defp object_data(object) do
    %{
      id: object.id,
      norad_id: object.norad_id,
      name: object.name,
      object_type: object.object_type,
      orbital_status: object.orbital_status
    }
  end
end
