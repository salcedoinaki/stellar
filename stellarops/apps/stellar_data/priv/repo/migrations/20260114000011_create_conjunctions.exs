defmodule StellarData.Repo.Migrations.CreateConjunctions do
  use Ecto.Migration

  def change do
    # Create conjunction severity enum
    execute(
      "CREATE TYPE conjunction_severity AS ENUM ('low', 'medium', 'high', 'critical')",
      "DROP TYPE conjunction_severity"
    )

    # Create conjunction status enum
    execute(
      "CREATE TYPE conjunction_status AS ENUM ('predicted', 'active', 'monitoring', 'avoided', 'passed', 'maneuver_executed')",
      "DROP TYPE conjunction_status"
    )

    create table(:conjunctions, primary_key: false) do
      add :id, :binary_id, primary_key: true

      # Objects involved
      add :primary_object_id, references(:space_objects, type: :binary_id, on_delete: :delete_all),
          null: false
      add :secondary_object_id, references(:space_objects, type: :binary_id, on_delete: :delete_all),
          null: false
      add :satellite_id, references(:satellites, type: :string, on_delete: :nilify_all)

      # Time of closest approach
      add :tca, :utc_datetime_usec, null: false
      add :tca_uncertainty_seconds, :float, default: 0.0

      # Miss distance components (meters)
      add :miss_distance_m, :float, null: false
      add :miss_distance_radial_m, :float
      add :miss_distance_in_track_m, :float
      add :miss_distance_cross_track_m, :float
      add :miss_distance_uncertainty_m, :float

      # Relative velocity (m/s)
      add :relative_velocity_ms, :float

      # Collision probability
      add :collision_probability, :float
      add :pc_method, :string

      # Combined object radius for hard body analysis
      add :combined_radius_m, :float, default: 10.0

      # Risk assessment
      add :severity, :conjunction_severity, default: "low", null: false
      add :status, :conjunction_status, default: "predicted", null: false

      # Screening volume (meters)
      add :screening_volume_radial_m, :float
      add :screening_volume_in_track_m, :float
      add :screening_volume_cross_track_m, :float

      # Covariance matrices (stored as JSON)
      add :primary_covariance, :map
      add :secondary_covariance, :map

      # COA tracking
      add :recommended_coa_id, :binary_id
      add :executed_maneuver_id, :binary_id

      # Source and tracking
      add :data_source, :string
      add :cdm_id, :string
      add :screening_date, :utc_datetime_usec
      add :last_updated, :utc_datetime_usec

      # Notes
      add :notes, :text

      timestamps(type: :utc_datetime_usec)
    end

    # Index for time-based queries
    create index(:conjunctions, [:tca])

    # Index for severity queries
    create index(:conjunctions, [:severity])

    # Index for status queries
    create index(:conjunctions, [:status])

    # Index for satellite queries
    create index(:conjunctions, [:satellite_id])

    # Index for object queries
    create index(:conjunctions, [:primary_object_id])
    create index(:conjunctions, [:secondary_object_id])

    # Index for CDM lookup
    create index(:conjunctions, [:cdm_id])

    # Composite index for upcoming critical events
    create index(:conjunctions, [:tca, :severity, :status])

    # Composite index for object pair lookups
    create index(:conjunctions, [:primary_object_id, :secondary_object_id, :tca])
  end
end
