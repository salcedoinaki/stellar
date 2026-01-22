defmodule StellarData.SpaceObjects.SpaceObject do
  @moduledoc """
  Ecto schema for tracked space objects.

  Represents any trackable object in orbit including:
  - Active satellites (owned or foreign)
  - Debris fragments
  - Unknown or unclassified objects
  - Potentially hostile/suspicious objects

  ## Fields
  - norad_id: NORAD catalog number (unique identifier)
  - name: Human-readable name or designation
  - international_designator: International designator (COSPAR ID)
  - object_type: Classification (satellite, debris, rocket_body, unknown)
  - owner: Operating nation or organization
  - status: Operational status (active, inactive, decayed, unknown)
  - orbit_type: LEO, MEO, GEO, HEO, etc.
  - capabilities: List of known capabilities
  - classification: Security classification (unclassified, confidential, secret)
  - threat_level: Threat assessment (none, low, medium, high, critical)

  ## TLE Data
  - tle_line1: First line of Two-Line Element set
  - tle_line2: Second line of TLE
  - tle_epoch: Epoch of the TLE data
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @timestamps_opts [type: :utc_datetime_usec]

  @object_types [:satellite, :debris, :rocket_body, :payload, :unknown]
  @statuses [:active, :inactive, :decayed, :unknown]
  @orbit_types [:leo, :meo, :geo, :heo, :sso, :polar, :equatorial, :unknown]
  @classifications [:unclassified, :confidential, :secret, :top_secret]
  @threat_levels [:none, :low, :medium, :high, :critical]

  schema "space_objects" do
    field :norad_id, :integer
    field :name, :string
    field :international_designator, :string
    field :object_type, Ecto.Enum, values: @object_types, default: :unknown
    field :owner, :string
    field :status, Ecto.Enum, values: @statuses, default: :unknown
    field :orbit_type, Ecto.Enum, values: @orbit_types, default: :unknown
    
    # Orbital parameters
    field :inclination_deg, :float
    field :apogee_km, :float
    field :perigee_km, :float
    field :period_minutes, :float
    field :semi_major_axis_km, :float
    field :eccentricity, :float
    field :raan_deg, :float
    field :arg_perigee_deg, :float
    field :mean_anomaly_deg, :float
    field :mean_motion, :float
    field :bstar_drag, :float
    
    # TLE data
    field :tle_line1, :string
    field :tle_line2, :string
    field :tle_epoch, :utc_datetime_usec
    field :tle_updated_at, :utc_datetime_usec
    
    # Capability and threat assessment
    field :capabilities, {:array, :string}, default: []
    field :classification, Ecto.Enum, values: @classifications, default: :unclassified
    field :threat_level, Ecto.Enum, values: @threat_levels, default: :none
    field :intel_summary, :string
    field :notes, :string
    
    # Physical characteristics
    field :radar_cross_section, :float
    field :size_class, :string
    field :launch_date, :date
    field :launch_site, :string
    
    # Tracking metadata
    field :last_observed_at, :utc_datetime_usec
    field :observation_count, :integer, default: 0
    field :data_source, :string
    
    # Foreign asset tracking (is this our satellite?)
    field :is_protected_asset, :boolean, default: false
    belongs_to :satellite, StellarData.Satellites.Satellite, type: :string

    timestamps()
  end

  @required_fields [:norad_id, :name]
  @optional_fields [
    :international_designator,
    :object_type,
    :owner,
    :status,
    :orbit_type,
    :inclination_deg,
    :apogee_km,
    :perigee_km,
    :period_minutes,
    :semi_major_axis_km,
    :eccentricity,
    :raan_deg,
    :arg_perigee_deg,
    :mean_anomaly_deg,
    :mean_motion,
    :bstar_drag,
    :tle_line1,
    :tle_line2,
    :tle_epoch,
    :tle_updated_at,
    :capabilities,
    :classification,
    :threat_level,
    :intel_summary,
    :notes,
    :radar_cross_section,
    :size_class,
    :launch_date,
    :launch_site,
    :last_observed_at,
    :observation_count,
    :data_source,
    :is_protected_asset,
    :satellite_id
  ]

  @doc """
  Creates a changeset for a space object.
  """
  def changeset(space_object, attrs) do
    space_object
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_number(:norad_id, greater_than: 0)
    |> validate_length(:name, min: 1, max: 255)
    |> validate_length(:tle_line1, is: 69)
    |> validate_length(:tle_line2, is: 69)
    |> validate_number(:inclination_deg, greater_than_or_equal_to: 0, less_than_or_equal_to: 180)
    |> validate_number(:eccentricity, greater_than_or_equal_to: 0, less_than: 1)
    |> unique_constraint(:norad_id)
    |> foreign_key_constraint(:satellite_id)
  end

  @doc """
  Updates threat assessment for an object.
  """
  def threat_changeset(space_object, attrs) do
    space_object
    |> cast(attrs, [:threat_level, :intel_summary, :capabilities, :classification, :notes])
  end

  @doc """
  Updates TLE data for an object.
  """
  def tle_changeset(space_object, attrs) do
    space_object
    |> cast(attrs, [:tle_line1, :tle_line2, :tle_epoch, :tle_updated_at])
    |> extract_orbital_elements_from_tle()
  end

  @doc """
  Marks an object as observed.
  """
  def observation_changeset(space_object) do
    space_object
    |> change(%{
      last_observed_at: DateTime.utc_now(),
      observation_count: (space_object.observation_count || 0) + 1
    })
  end

  # Extract orbital elements from TLE if present
  defp extract_orbital_elements_from_tle(changeset) do
    case {get_change(changeset, :tle_line1), get_change(changeset, :tle_line2)} do
      {nil, _} -> changeset
      {_, nil} -> changeset
      {line1, line2} ->
        case parse_tle_elements(line1, line2) do
          {:ok, elements} ->
            changeset
            |> put_change(:inclination_deg, elements.inclination)
            |> put_change(:eccentricity, elements.eccentricity)
            |> put_change(:raan_deg, elements.raan)
            |> put_change(:arg_perigee_deg, elements.arg_perigee)
            |> put_change(:mean_anomaly_deg, elements.mean_anomaly)
            |> put_change(:mean_motion, elements.mean_motion)
            |> put_change(:bstar_drag, elements.bstar)
          {:error, _} ->
            changeset
        end
    end
  end

  # Parse TLE line 2 to extract orbital elements
  defp parse_tle_elements(_line1, line2) do
    try do
      # TLE Line 2 format:
      # Columns 9-16: Inclination (degrees)
      # Columns 18-25: Right Ascension of Ascending Node (degrees)
      # Columns 27-33: Eccentricity (decimal point assumed)
      # Columns 35-42: Argument of Perigee (degrees)
      # Columns 44-51: Mean Anomaly (degrees)
      # Columns 53-63: Mean Motion (revolutions per day)

      inclination = line2 |> String.slice(8..15) |> String.trim() |> String.to_float()
      raan = line2 |> String.slice(17..24) |> String.trim() |> String.to_float()
      ecc_str = line2 |> String.slice(26..32) |> String.trim()
      eccentricity = String.to_float("0." <> ecc_str)
      arg_perigee = line2 |> String.slice(34..41) |> String.trim() |> String.to_float()
      mean_anomaly = line2 |> String.slice(43..50) |> String.trim() |> String.to_float()
      mean_motion = line2 |> String.slice(52..62) |> String.trim() |> String.to_float()

      {:ok, %{
        inclination: inclination,
        raan: raan,
        eccentricity: eccentricity,
        arg_perigee: arg_perigee,
        mean_anomaly: mean_anomaly,
        mean_motion: mean_motion,
        bstar: nil  # Would need to parse from line 1
      }}
    rescue
      _ -> {:error, :parse_failed}
    end
  end
end
