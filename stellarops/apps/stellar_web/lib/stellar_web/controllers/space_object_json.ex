defmodule StellarWeb.SpaceObjectJSON do
  @moduledoc """
  JSON rendering for space objects.
  """

  alias StellarData.SpaceObjects.SpaceObject
  alias StellarData.Threats.ThreatAssessment

  @doc """
  Renders a list of space objects.
  """
  def index(%{objects: objects}) do
    %{data: for(object <- objects, do: data(object, nil))}
  end

  @doc """
  Renders a single space object.
  """
  def show(%{object: object, threat_assessment: threat_assessment}) do
    %{data: data(object, threat_assessment)}
  end

  defp data(%SpaceObject{} = object, threat_assessment) do
    base_data = %{
      id: object.id,
      norad_id: object.norad_id,
      name: object.name,
      international_designator: object.international_designator,
      object_type: object.object_type,
      owner: object.owner,
      country_code: object.country_code,
      launch_date: object.launch_date,
      orbital_status: object.orbital_status,
      tle_line1: object.tle_line1,
      tle_line2: object.tle_line2,
      tle_epoch: object.tle_epoch,
      apogee_km: object.apogee_km,
      perigee_km: object.perigee_km,
      inclination_deg: object.inclination_deg,
      period_min: object.period_min,
      rcs_meters: object.rcs_meters,
      notes: object.notes,
      inserted_at: object.inserted_at,
      updated_at: object.updated_at
    }

    case threat_assessment do
      nil -> base_data
      assessment -> Map.put(base_data, :threat_assessment, threat_data(assessment))
    end
  end

  defp threat_data(%ThreatAssessment{} = assessment) do
    %{
      id: assessment.id,
      classification: assessment.classification,
      capabilities: assessment.capabilities,
      threat_level: assessment.threat_level,
      intel_summary: assessment.intel_summary,
      notes: assessment.notes,
      assessed_by: assessment.assessed_by,
      assessed_at: assessment.assessed_at,
      confidence_level: assessment.confidence_level,
      updated_at: assessment.updated_at
    }
  end
end
