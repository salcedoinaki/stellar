defmodule StellarData.COA.CourseOfAction do
  @moduledoc """
  Ecto schema for Course of Action recommendations.

  A COA represents a recommended response to a threat, particularly
  for collision avoidance maneuvers but also other defensive actions.

  ## Types of COAs
  - avoidance_maneuver: Orbital maneuver to avoid collision
  - monitor: Continue monitoring without action
  - alert: Notify operators for human decision
  - defensive_posture: Change satellite operational mode
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @timestamps_opts [type: :utc_datetime_usec]

  @coa_types [:avoidance_maneuver, :monitor, :alert, :defensive_posture, :no_action]
  @statuses [:proposed, :approved, :rejected, :executing, :completed, :failed, :superseded]
  @priorities [:low, :medium, :high, :critical]

  schema "courses_of_action" do
    # Reference to the threat
    belongs_to :conjunction, StellarData.Conjunctions.Conjunction, type: :binary_id
    belongs_to :satellite, StellarData.Satellites.Satellite, type: :string

    # COA classification
    field :coa_type, Ecto.Enum, values: @coa_types
    field :priority, Ecto.Enum, values: @priorities, default: :medium
    field :status, Ecto.Enum, values: @statuses, default: :proposed

    # Maneuver parameters (for avoidance_maneuver type)
    field :maneuver_time, :utc_datetime_usec
    field :delta_v_ms, :float
    field :delta_v_radial_ms, :float
    field :delta_v_in_track_ms, :float
    field :delta_v_cross_track_ms, :float
    field :burn_duration_s, :float
    field :fuel_cost_kg, :float

    # Post-maneuver predictions
    field :post_maneuver_miss_distance_m, :float
    field :post_maneuver_probability, :float
    field :new_orbit_apogee_km, :float
    field :new_orbit_perigee_km, :float

    # Risk and impact assessment
    field :risk_if_no_action, :float  # 0.0 to 1.0
    field :effectiveness_score, :float  # 0.0 to 1.0
    field :mission_impact_score, :float  # 0.0 to 1.0 (lower is better)
    field :overall_score, :float  # Combined recommendation score

    # Decision tracking
    field :decision_deadline, :utc_datetime_usec
    field :decided_by, :string
    field :decided_at, :utc_datetime_usec
    field :decision_notes, :string

    # Execution tracking
    field :command_id, :binary_id
    field :execution_started_at, :utc_datetime_usec
    field :execution_completed_at, :utc_datetime_usec
    field :execution_result, :map

    # Description and rationale
    field :title, :string
    field :description, :string
    field :rationale, :string
    field :risks, {:array, :string}, default: []
    field :assumptions, {:array, :string}, default: []

    # Alternative COAs (references to other COA IDs)
    field :alternative_coa_ids, {:array, :binary_id}, default: []

    timestamps()
  end

  @required_fields [:coa_type, :satellite_id]
  @optional_fields [
    :conjunction_id,
    :priority,
    :status,
    :maneuver_time,
    :delta_v_ms,
    :delta_v_radial_ms,
    :delta_v_in_track_ms,
    :delta_v_cross_track_ms,
    :burn_duration_s,
    :fuel_cost_kg,
    :post_maneuver_miss_distance_m,
    :post_maneuver_probability,
    :new_orbit_apogee_km,
    :new_orbit_perigee_km,
    :risk_if_no_action,
    :effectiveness_score,
    :mission_impact_score,
    :overall_score,
    :decision_deadline,
    :decided_by,
    :decided_at,
    :decision_notes,
    :command_id,
    :execution_started_at,
    :execution_completed_at,
    :execution_result,
    :title,
    :description,
    :rationale,
    :risks,
    :assumptions,
    :alternative_coa_ids
  ]

  def changeset(coa, attrs) do
    coa
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_number(:delta_v_ms, greater_than_or_equal_to: 0)
    |> validate_number(:fuel_cost_kg, greater_than_or_equal_to: 0)
    |> validate_number(:overall_score, greater_than_or_equal_to: 0, less_than_or_equal_to: 1)
    |> compute_overall_score()
    |> foreign_key_constraint(:conjunction_id)
    |> foreign_key_constraint(:satellite_id)
  end

  def decision_changeset(coa, attrs) do
    coa
    |> cast(attrs, [:status, :decided_by, :decided_at, :decision_notes])
    |> validate_required([:status, :decided_by])
    |> put_change(:decided_at, DateTime.utc_now())
  end

  def execution_changeset(coa, attrs) do
    coa
    |> cast(attrs, [:status, :command_id, :execution_started_at, :execution_completed_at, :execution_result])
  end

  defp compute_overall_score(changeset) do
    # If overall_score is already set, don't recompute
    case get_field(changeset, :overall_score) do
      nil ->
        effectiveness = get_field(changeset, :effectiveness_score) || 0.5
        mission_impact = get_field(changeset, :mission_impact_score) || 0.5
        risk = get_field(changeset, :risk_if_no_action) || 0.5

        # Higher is better: effectiveness and risk reduction weighted more than mission impact
        # Score = 0.4 * effectiveness + 0.35 * risk_addressed + 0.25 * (1 - mission_impact)
        overall = 0.4 * effectiveness + 0.35 * risk + 0.25 * (1.0 - mission_impact)
        put_change(changeset, :overall_score, Float.round(overall, 4))

      _ ->
        changeset
    end
  end
end
