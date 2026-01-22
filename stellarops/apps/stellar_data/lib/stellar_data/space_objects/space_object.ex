defmodule StellarData.SpaceObjects.SpaceObject do
  @moduledoc """
  Schema for space objects (satellites, debris, rocket bodies, etc.)
  
  Stores orbital elements, TLE data, and metadata for tracked space objects.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @type_values ~w(satellite debris rocket_body unknown)
  @status_values ~w(active decayed retired unknown)

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "space_objects" do
    field :norad_id, :integer
    field :name, :string
    field :international_designator, :string
    field :object_type, :string, default: "unknown"
    field :owner, :string
    field :country_code, :string
    field :launch_date, :date
    field :orbital_status, :string, default: "unknown"

    # TLE data
    field :tle_line1, :string
    field :tle_line2, :string
    field :tle_epoch, :utc_datetime

    # Derived orbital parameters (from TLE)
    field :apogee_km, :float
    field :perigee_km, :float
    field :inclination_deg, :float
    field :period_min, :float
    field :rcs_meters, :float

    # Metadata
    field :notes, :string

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset for creating or updating a space object.
  """
  def changeset(space_object, attrs) do
    space_object
    |> cast(attrs, [
      :norad_id,
      :name,
      :international_designator,
      :object_type,
      :owner,
      :country_code,
      :launch_date,
      :orbital_status,
      :tle_line1,
      :tle_line2,
      :tle_epoch,
      :apogee_km,
      :perigee_km,
      :inclination_deg,
      :period_min,
      :rcs_meters,
      :notes
    ])
    |> validate_required([:norad_id, :name])
    |> validate_inclusion(:object_type, @type_values)
    |> validate_inclusion(:orbital_status, @status_values)
    |> validate_number(:norad_id, greater_than: 0)
    |> validate_tle()
    |> unique_constraint(:norad_id)
  end

  @doc """
  Changeset for updating TLE data.
  """
  def tle_changeset(space_object, attrs) do
    space_object
    |> cast(attrs, [:tle_line1, :tle_line2, :tle_epoch])
    |> validate_tle()
  end

  defp validate_tle(changeset) do
    line1 = get_field(changeset, :tle_line1)
    line2 = get_field(changeset, :tle_line2)

    cond do
      is_nil(line1) and is_nil(line2) ->
        changeset

      is_nil(line1) or is_nil(line2) ->
        changeset
        |> add_error(:tle_line1, "both TLE lines must be provided together")

      String.length(line1) != 69 ->
        changeset
        |> add_error(:tle_line1, "must be exactly 69 characters")

      String.length(line2) != 69 ->
        changeset
        |> add_error(:tle_line2, "must be exactly 69 characters")

      !String.starts_with?(line1, "1 ") ->
        changeset
        |> add_error(:tle_line1, "must start with '1 '")

      !String.starts_with?(line2, "2 ") ->
        changeset
        |> add_error(:tle_line2, "must start with '2 '")

      true ->
        changeset
    end
  end
end
