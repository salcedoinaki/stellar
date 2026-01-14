defmodule StellarData.Telemetry.TelemetryEvent do
  @moduledoc """
  Ecto schema for telemetry events.

  Stores telemetry data points from satellites including
  sensor readings, state changes, and system metrics.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @timestamps_opts [type: :utc_datetime_usec]

  schema "telemetry_events" do
    field :event_type, :string
    field :data, :map, default: %{}
    field :recorded_at, :utc_datetime_usec

    belongs_to :satellite, StellarData.Satellites.Satellite, type: :string

    timestamps()
  end

  @required_fields [:satellite_id, :event_type, :recorded_at]
  @optional_fields [:data]

  @doc """
  Creates a changeset for a telemetry event.
  """
  def changeset(event, attrs) do
    event
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_length(:event_type, min: 1, max: 100)
    |> foreign_key_constraint(:satellite_id)
  end
end
