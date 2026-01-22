defmodule StellarData.Satellites.Satellite do
  @moduledoc """
  Ecto schema representing a persisted satellite.

  This stores the static configuration and last known state of a satellite.
  The live state is maintained by the GenServer in stellar_core.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @type mode :: :nominal | :safe | :survival

  @primary_key {:id, :string, autogenerate: false}
  @timestamps_opts [type: :utc_datetime_usec]

  schema "satellites" do
    field :name, :string
    field :norad_id, :string
    field :mode, Ecto.Enum, values: [:nominal, :safe, :survival], default: :nominal
    field :energy, :float, default: 100.0
    field :memory_used, :float, default: 0.0
    field :position_x, :float, default: 0.0
    field :position_y, :float, default: 0.0
    field :position_z, :float, default: 0.0
    field :tle_line1, :string
    field :tle_line2, :string
    field :tle_epoch, :utc_datetime_usec
    field :tle_updated_at, :utc_datetime_usec
    field :launched_at, :utc_datetime_usec
    field :active, :boolean, default: true

    has_many :telemetry_events, StellarData.Telemetry.TelemetryEvent
    has_many :commands, StellarData.Commands.Command

    timestamps()
  end

  @required_fields [:id]
  @optional_fields [
    :name,
    :norad_id,
    :mode,
    :energy,
    :memory_used,
    :position_x,
    :position_y,
    :position_z,
    :tle_line1,
    :tle_line2,
    :tle_epoch,
    :tle_updated_at,
    :launched_at,
    :active
  ]

  @doc """
  Creates a changeset for inserting a new satellite.
  """
  def changeset(satellite, attrs) do
    satellite
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_number(:energy, greater_than_or_equal_to: 0, less_than_or_equal_to: 100)
    |> validate_number(:memory_used, greater_than_or_equal_to: 0)
    |> unique_constraint(:id, name: :satellites_pkey)
  end

  @doc """
  Creates a changeset for updating satellite state.
  """
  def state_changeset(satellite, attrs) do
    satellite
    |> cast(attrs, [:mode, :energy, :memory_used, :position_x, :position_y, :position_z, :active])
    |> validate_number(:energy, greater_than_or_equal_to: 0, less_than_or_equal_to: 100)
    |> validate_number(:memory_used, greater_than_or_equal_to: 0)
  end
end
