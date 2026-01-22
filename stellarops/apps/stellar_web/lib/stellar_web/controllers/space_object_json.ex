defmodule StellarWeb.SpaceObjectJSON do
  @moduledoc """
  JSON rendering for space object endpoints.
  """

  alias StellarData.SpaceObjects.SpaceObject

  @doc """
  Renders a list of space objects.
  """
  def index(%{space_objects: space_objects}) do
    %{data: for(object <- space_objects, do: data(object))}
  end

  @doc """
  Renders a single space object.
  """
  def show(%{space_object: space_object}) do
    %{data: data(space_object)}
  end

  defp data(%SpaceObject{} = object) do
    %{
      id: object.id,
      norad_id: object.norad_id,
      name: object.name,
      international_designator: object.international_designator,
      object_type: object.object_type,
      owner: object.owner,
      status: object.status,
      orbit_type: object.orbit_type,
      orbital_parameters: %{
        inclination_deg: object.inclination_deg,
        apogee_km: object.apogee_km,
        perigee_km: object.perigee_km,
        period_minutes: object.period_minutes,
        semi_major_axis_km: object.semi_major_axis_km,
        eccentricity: object.eccentricity,
        raan_deg: object.raan_deg,
        arg_perigee_deg: object.arg_perigee_deg,
        mean_anomaly_deg: object.mean_anomaly_deg,
        mean_motion: object.mean_motion,
        bstar_drag: object.bstar_drag
      },
      tle: %{
        line1: object.tle_line1,
        line2: object.tle_line2,
        epoch: object.tle_epoch,
        updated_at: object.tle_updated_at
      },
      threat_assessment: %{
        threat_level: object.threat_level,
        classification: object.classification,
        capabilities: object.capabilities,
        intel_summary: object.intel_summary
      },
      physical_characteristics: %{
        radar_cross_section: object.radar_cross_section,
        size_class: object.size_class,
        launch_date: object.launch_date,
        launch_site: object.launch_site
      },
      tracking: %{
        last_observed_at: object.last_observed_at,
        observation_count: object.observation_count,
        data_source: object.data_source
      },
      is_protected_asset: object.is_protected_asset,
      satellite_id: object.satellite_id,
      notes: object.notes,
      inserted_at: object.inserted_at,
      updated_at: object.updated_at
    }
  end
end
