defmodule StellarData.Conjunctions.Conjunction do
  @moduledoc """
  Ecto schema for conjunction events between space objects.

  A conjunction represents a close approach between two space objects,
  which could indicate a potential collision risk.

  ## Key Fields
  - primary_object: The protected asset (our satellite or high-value target)
  - secondary_object: The approaching object
  - tca: Time of Closest Approach
  - miss_distance: Predicted minimum separation distance

  ## Risk Assessment
  - collision_probability: Probability of collision (0.0 to 1.0)
  - severity: Risk classification based on miss distance and probability
  - status: Event lifecycle (predicted, active, monitoring, avoided, occurred)
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @timestamps_opts [type: :utc_datetime_usec]

  @severities [:low, :medium, :high, :critical]
  @statuses [:predicted, :active, :monitoring, :avoided, :passed, :maneuver_executed]

  schema "conjunctions" do
    # Objects involved
    belongs_to :primary_object, StellarData.SpaceObjects.SpaceObject, type: :binary_id
    belongs_to :secondary_object, StellarData.SpaceObjects.SpaceObject, type: :binary_id
    
    # If primary is one of our satellites
    belongs_to :satellite, StellarData.Satellites.Satellite, type: :string

    # Time of closest approach
    field :tca, :utc_datetime_usec
    field :tca_uncertainty_seconds, :float, default: 0.0

    # Miss distance in meters
    field :miss_distance_m, :float
    field :miss_distance_radial_m, :float
    field :miss_distance_in_track_m, :float
    field :miss_distance_cross_track_m, :float
    field :miss_distance_uncertainty_m, :float

    # Relative velocity at TCA (m/s)
    field :relative_velocity_ms, :float

    # Collision probability (Pc)
    field :collision_probability, :float
    field :pc_method, :string  # Method used for Pc calculation (e.g., "Alfano", "Foster")

    # Combined hard body radius (sum of object radii)
    field :combined_radius_m, :float, default: 10.0

    # Risk assessment
    field :severity, Ecto.Enum, values: @severities, default: :low
    field :status, Ecto.Enum, values: @statuses, default: :predicted

    # Screening parameters
    field :screening_volume_radial_m, :float
    field :screening_volume_in_track_m, :float
    field :screening_volume_cross_track_m, :float

    # Covariance data (for advanced Pc calculation)
    field :primary_covariance, :map
    field :secondary_covariance, :map

    # COA (Course of Action) reference
    field :recommended_coa_id, :binary_id
    field :executed_maneuver_id, :binary_id

    # Source and update tracking
    field :data_source, :string
    field :cdm_id, :string  # Conjunction Data Message ID
    field :screening_date, :utc_datetime_usec
    field :last_updated, :utc_datetime_usec

    # Analysis notes
    field :notes, :string

    timestamps()
  end

  @required_fields [:primary_object_id, :secondary_object_id, :tca, :miss_distance_m]
  @optional_fields [
    :satellite_id,
    :tca_uncertainty_seconds,
    :miss_distance_radial_m,
    :miss_distance_in_track_m,
    :miss_distance_cross_track_m,
    :miss_distance_uncertainty_m,
    :relative_velocity_ms,
    :collision_probability,
    :pc_method,
    :combined_radius_m,
    :severity,
    :status,
    :screening_volume_radial_m,
    :screening_volume_in_track_m,
    :screening_volume_cross_track_m,
    :primary_covariance,
    :secondary_covariance,
    :recommended_coa_id,
    :executed_maneuver_id,
    :data_source,
    :cdm_id,
    :screening_date,
    :last_updated,
    :notes
  ]

  @doc """
  Creates a changeset for a conjunction event.
  """
  def changeset(conjunction, attrs) do
    conjunction
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_number(:miss_distance_m, greater_than_or_equal_to: 0)
    |> validate_number(:collision_probability, greater_than_or_equal_to: 0, less_than_or_equal_to: 1)
    |> compute_severity()
    |> foreign_key_constraint(:primary_object_id)
    |> foreign_key_constraint(:secondary_object_id)
    |> foreign_key_constraint(:satellite_id)
  end

  @doc """
  Updates status of a conjunction.
  """
  def status_changeset(conjunction, new_status) do
    conjunction
    |> change(%{status: new_status, last_updated: DateTime.utc_now()})
  end

  @doc """
  Updates conjunction with COA recommendation.
  """
  def coa_changeset(conjunction, coa_id) do
    conjunction
    |> change(%{recommended_coa_id: coa_id, last_updated: DateTime.utc_now()})
  end

  @doc """
  Marks conjunction as having an executed maneuver.
  """
  def maneuver_changeset(conjunction, maneuver_id) do
    conjunction
    |> change(%{
      executed_maneuver_id: maneuver_id,
      status: :maneuver_executed,
      last_updated: DateTime.utc_now()
    })
  end

  # Compute severity based on miss distance and collision probability
  defp compute_severity(changeset) do
    miss_distance = get_field(changeset, :miss_distance_m)
    probability = get_field(changeset, :collision_probability)

    severity = cond do
      # Critical: Very close approach or high probability
      (miss_distance != nil and miss_distance < 100) or
      (probability != nil and probability > 1.0e-4) ->
        :critical

      # High: Close approach or moderate probability
      (miss_distance != nil and miss_distance < 500) or
      (probability != nil and probability > 1.0e-5) ->
        :high

      # Medium: Within screening threshold
      (miss_distance != nil and miss_distance < 1000) or
      (probability != nil and probability > 1.0e-6) ->
        :medium

      # Low: Far approach
      true ->
        :low
    end

    put_change(changeset, :severity, severity)
  end
end
