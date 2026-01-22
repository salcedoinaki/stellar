defmodule StellarData.Repo.Migrations.CreateCoursesOfAction do
  use Ecto.Migration

  def change do
    # Create COA type enum
    execute(
      "CREATE TYPE coa_type AS ENUM ('avoidance_maneuver', 'monitor', 'alert', 'defensive_posture', 'no_action')",
      "DROP TYPE coa_type"
    )

    # Create COA status enum
    execute(
      "CREATE TYPE coa_status AS ENUM ('proposed', 'approved', 'rejected', 'executing', 'completed', 'failed', 'superseded')",
      "DROP TYPE coa_status"
    )

    # Create COA priority enum
    execute(
      "CREATE TYPE coa_priority AS ENUM ('low', 'medium', 'high', 'critical')",
      "DROP TYPE coa_priority"
    )

    create table(:courses_of_action, primary_key: false) do
      add :id, :binary_id, primary_key: true

      # References
      add :conjunction_id, references(:conjunctions, type: :binary_id, on_delete: :nilify_all)
      add :satellite_id, references(:satellites, type: :string, on_delete: :delete_all), null: false

      # Classification
      add :coa_type, :coa_type, null: false
      add :priority, :coa_priority, default: "medium", null: false
      add :status, :coa_status, default: "proposed", null: false

      # Maneuver parameters
      add :maneuver_time, :utc_datetime_usec
      add :delta_v_ms, :float
      add :delta_v_radial_ms, :float
      add :delta_v_in_track_ms, :float
      add :delta_v_cross_track_ms, :float
      add :burn_duration_s, :float
      add :fuel_cost_kg, :float

      # Post-maneuver predictions
      add :post_maneuver_miss_distance_m, :float
      add :post_maneuver_probability, :float
      add :new_orbit_apogee_km, :float
      add :new_orbit_perigee_km, :float

      # Risk assessment
      add :risk_if_no_action, :float
      add :effectiveness_score, :float
      add :mission_impact_score, :float
      add :overall_score, :float

      # Decision tracking
      add :decision_deadline, :utc_datetime_usec
      add :decided_by, :string
      add :decided_at, :utc_datetime_usec
      add :decision_notes, :text

      # Execution tracking
      add :command_id, :binary_id
      add :execution_started_at, :utc_datetime_usec
      add :execution_completed_at, :utc_datetime_usec
      add :execution_result, :map

      # Description
      add :title, :string
      add :description, :text
      add :rationale, :text
      add :risks, {:array, :string}, default: []
      add :assumptions, {:array, :string}, default: []

      # Alternatives
      add :alternative_coa_ids, {:array, :binary_id}, default: []

      timestamps(type: :utc_datetime_usec)
    end

    # Index for conjunction queries
    create index(:courses_of_action, [:conjunction_id])

    # Index for satellite queries
    create index(:courses_of_action, [:satellite_id])

    # Index for status queries
    create index(:courses_of_action, [:status])

    # Index for priority queries
    create index(:courses_of_action, [:priority])

    # Index for pending decisions (status + deadline)
    create index(:courses_of_action, [:status, :decision_deadline])

    # Index for scoring/ranking
    create index(:courses_of_action, [:overall_score])
  end
end
