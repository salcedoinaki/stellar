defmodule StellarData.COAs.COA do
  @moduledoc """
  Schema for Course of Action (COA) planning.

  A COA represents a possible response to a detected conjunction, typically
  involving an orbital maneuver to increase miss distance and reduce collision risk.

  COA Types:
  - retrograde_burn: Decrease orbital velocity to lower orbit
  - prograde_burn: Increase orbital velocity to raise orbit
  - inclination_change: Change orbital plane
  - phasing: Adjust timing to avoid collision point
  - flyby: Intercept trajectory for defensive purposes
  - station_keeping: Maintain current orbit (no action)
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  # TASK-292: Valid COA types
  @coa_types ~w(retrograde_burn prograde_burn inclination_change phasing flyby station_keeping)

  # TASK-301: Valid status values
  @statuses ~w(proposed selected executing completed failed rejected)

  schema "coas" do
    # TASK-291: Relationship to conjunction
    belongs_to :conjunction, StellarData.Conjunctions.Conjunction

    # TASK-292: COA type
    field :type, Ecto.Enum, values: [:retrograde_burn, :prograde_burn, :inclination_change,
                                     :phasing, :flyby, :station_keeping]

    # TASK-293: Basic info
    field :name, :string
    field :objective, :string
    field :description, :string

    # TASK-294-295: Delta-V parameters
    field :delta_v_magnitude, :float
    field :delta_v_direction, :map  # {x, y, z} unit vector

    # TASK-296-297: Burn timing
    field :burn_start_time, :utc_datetime
    field :burn_duration_seconds, :float

    # TASK-298: Fuel consumption
    field :estimated_fuel_kg, :float

    # TASK-299: Predicted outcome
    field :predicted_miss_distance_km, :float

    # TASK-300: Risk assessment (0-100)
    field :risk_score, :float

    # TASK-301: Status tracking
    field :status, Ecto.Enum, values: [:proposed, :selected, :executing, :completed, :failed, :rejected],
      default: :proposed

    # TASK-302-303: Orbital elements (Keplerian)
    # {a: semi_major_axis, e: eccentricity, i: inclination, raan: right_ascension,
    #  argp: argument_of_periapsis, ta: true_anomaly}
    field :pre_burn_orbit, :map
    field :post_burn_orbit, :map

    # TASK-304: Selection tracking
    field :selected_at, :utc_datetime
    field :selected_by, :string

    # Execution tracking
    field :executed_at, :utc_datetime
    field :completed_at, :utc_datetime
    field :failure_reason, :string

    # Associations
    has_many :missions, StellarData.Missions.Mission, foreign_key: :coa_id

    timestamps(type: :utc_datetime)
  end

  @doc """
  Creates a changeset for a COA.
  """
  def changeset(coa, attrs) do
    coa
    |> cast(attrs, [
      :conjunction_id,
      :type,
      :name,
      :objective,
      :description,
      :delta_v_magnitude,
      :delta_v_direction,
      :burn_start_time,
      :burn_duration_seconds,
      :estimated_fuel_kg,
      :predicted_miss_distance_km,
      :risk_score,
      :status,
      :pre_burn_orbit,
      :post_burn_orbit,
      :selected_at,
      :selected_by,
      :executed_at,
      :completed_at,
      :failure_reason
    ])
    |> validate_required([:conjunction_id, :type, :name, :delta_v_magnitude])
    |> validate_inclusion(:type, [:retrograde_burn, :prograde_burn, :inclination_change,
                                   :phasing, :flyby, :station_keeping])
    |> validate_inclusion(:status, [:proposed, :selected, :executing, :completed, :failed, :rejected])
    |> validate_number(:delta_v_magnitude, greater_than_or_equal_to: 0)
    |> validate_number(:risk_score, greater_than_or_equal_to: 0, less_than_or_equal_to: 100)
    |> validate_number(:estimated_fuel_kg, greater_than_or_equal_to: 0)
    |> validate_number(:burn_duration_seconds, greater_than_or_equal_to: 0)
    |> validate_number(:predicted_miss_distance_km, greater_than_or_equal_to: 0)
    |> foreign_key_constraint(:conjunction_id)
    |> validate_delta_v_direction()
  end

  @doc """
  Changeset for selecting a COA.
  """
  def select_changeset(coa, selected_by) do
    coa
    |> change(%{
      status: :selected,
      selected_at: DateTime.utc_now(),
      selected_by: selected_by
    })
  end

  @doc """
  Changeset for starting COA execution.
  """
  def execute_changeset(coa) do
    coa
    |> change(%{
      status: :executing,
      executed_at: DateTime.utc_now()
    })
  end

  @doc """
  Changeset for completing COA execution.
  """
  def complete_changeset(coa) do
    coa
    |> change(%{
      status: :completed,
      completed_at: DateTime.utc_now()
    })
  end

  @doc """
  Changeset for failing COA execution.
  """
  def fail_changeset(coa, reason) do
    coa
    |> change(%{
      status: :failed,
      failure_reason: reason
    })
  end

  @doc """
  Changeset for rejecting a COA.
  """
  def reject_changeset(coa) do
    coa
    |> change(%{status: :rejected})
  end

  @doc """
  Changeset for rejecting a COA with rejection details.
  """
  def reject_changeset(coa, rejected_by, notes) do
    coa
    |> change(%{
      status: :rejected,
      selected_by: rejected_by,
      failure_reason: notes
    })
  end

  @doc """
  Changeset for approving a COA.
  """
  def approve_changeset(coa, approved_by) do
    coa
    |> change(%{
      status: :selected,
      selected_at: DateTime.utc_now(),
      selected_by: approved_by
    })
  end

  # Private helpers

  defp validate_delta_v_direction(changeset) do
    case get_field(changeset, :delta_v_direction) do
      nil ->
        changeset

      direction when is_map(direction) ->
        if Map.has_key?(direction, "x") and Map.has_key?(direction, "y") and Map.has_key?(direction, "z") do
          changeset
        else
          add_error(changeset, :delta_v_direction, "must contain x, y, z components")
        end

      _ ->
        add_error(changeset, :delta_v_direction, "must be a map with x, y, z components")
    end
  end
end
