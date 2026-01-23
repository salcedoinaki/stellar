defmodule StellarData.Conjunctions.Conjunction do
  @moduledoc """
  Schema for conjunction events (close approaches between objects).
  
  Tracks predicted close approaches, time of closest approach (TCA),
  miss distance, relative velocity, and collision probability.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias StellarData.SpaceObjects.SpaceObject

  @severity_values ~w(critical high medium low)
  @status_values ~w(active monitoring resolved expired)

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "conjunctions" do
    # Our satellite
    field :asset_id, :binary_id
    # Threat or debris object
    belongs_to :object, SpaceObject, foreign_key: :object_id

    # Conjunction metrics
    field :tca, :utc_datetime
    field :miss_distance_km, :float
    field :relative_velocity_km_s, :float
    field :probability_of_collision, :float

    # Classification
    field :severity, :string
    field :status, :string, default: "active"

    # Positions at TCA (JSON: {x, y, z})
    field :asset_position_at_tca, :map
    field :object_position_at_tca, :map

    # Covariance data for uncertainty (JSON)
    field :covariance_data, :map

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset for creating or updating a conjunction.
  """
  def changeset(conjunction, attrs) do
    conjunction
    |> cast(attrs, [
      :asset_id,
      :object_id,
      :tca,
      :miss_distance_km,
      :relative_velocity_km_s,
      :probability_of_collision,
      :severity,
      :status,
      :asset_position_at_tca,
      :object_position_at_tca,
      :covariance_data
    ])
    |> validate_required([
      :asset_id,
      :object_id,
      :tca,
      :miss_distance_km,
      :severity
    ])
    |> validate_inclusion(:severity, @severity_values)
    |> validate_inclusion(:status, @status_values)
    |> validate_number(:miss_distance_km, greater_than_or_equal_to: 0.0)
    |> validate_number(:relative_velocity_km_s, greater_than_or_equal_to: 0.0)
    |> validate_number(:probability_of_collision,
      greater_than_or_equal_to: 0.0,
      less_than_or_equal_to: 1.0
    )
    |> foreign_key_constraint(:object_id)
  end

  @doc """
  Changeset for updating conjunction status.
  """
  def status_changeset(conjunction, attrs) do
    conjunction
    |> cast(attrs, [:status])
    |> validate_inclusion(:status, @status_values)
  end
end
