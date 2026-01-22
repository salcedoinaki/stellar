defmodule StellarData.Repo.Migrations.CreateSpaceObjects do
  use Ecto.Migration

  def change do
    # Create object type enum
    execute(
      "CREATE TYPE space_object_type AS ENUM ('satellite', 'debris', 'rocket_body', 'payload', 'unknown')",
      "DROP TYPE space_object_type"
    )

    # Create status enum
    execute(
      "CREATE TYPE space_object_status AS ENUM ('active', 'inactive', 'decayed', 'unknown')",
      "DROP TYPE space_object_status"
    )

    # Create orbit type enum
    execute(
      "CREATE TYPE orbit_type AS ENUM ('leo', 'meo', 'geo', 'heo', 'sso', 'polar', 'equatorial', 'unknown')",
      "DROP TYPE orbit_type"
    )

    # Create classification enum
    execute(
      "CREATE TYPE security_classification AS ENUM ('unclassified', 'confidential', 'secret', 'top_secret')",
      "DROP TYPE security_classification"
    )

    # Create threat level enum
    execute(
      "CREATE TYPE threat_level AS ENUM ('none', 'low', 'medium', 'high', 'critical')",
      "DROP TYPE threat_level"
    )

    create table(:space_objects, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :norad_id, :integer, null: false
      add :name, :string, null: false
      add :international_designator, :string
      add :object_type, :space_object_type, default: "unknown", null: false
      add :owner, :string
      add :status, :space_object_status, default: "unknown", null: false
      add :orbit_type, :orbit_type, default: "unknown", null: false

      # Orbital parameters
      add :inclination_deg, :float
      add :apogee_km, :float
      add :perigee_km, :float
      add :period_minutes, :float
      add :semi_major_axis_km, :float
      add :eccentricity, :float
      add :raan_deg, :float
      add :arg_perigee_deg, :float
      add :mean_anomaly_deg, :float
      add :mean_motion, :float
      add :bstar_drag, :float

      # TLE data
      add :tle_line1, :string, size: 70
      add :tle_line2, :string, size: 70
      add :tle_epoch, :utc_datetime_usec
      add :tle_updated_at, :utc_datetime_usec

      # Capability and threat assessment
      add :capabilities, {:array, :string}, default: []
      add :classification, :security_classification, default: "unclassified", null: false
      add :threat_level, :threat_level, default: "none", null: false
      add :intel_summary, :text
      add :notes, :text

      # Physical characteristics
      add :radar_cross_section, :float
      add :size_class, :string
      add :launch_date, :date
      add :launch_site, :string

      # Tracking metadata
      add :last_observed_at, :utc_datetime_usec
      add :observation_count, :integer, default: 0
      add :data_source, :string

      # Link to managed satellite
      add :is_protected_asset, :boolean, default: false, null: false
      add :satellite_id, references(:satellites, type: :string, on_delete: :nilify_all)

      timestamps(type: :utc_datetime_usec)
    end

    # Unique constraint on NORAD ID
    create unique_index(:space_objects, [:norad_id])

    # Index for fast queries by type
    create index(:space_objects, [:object_type])

    # Index for threat level queries
    create index(:space_objects, [:threat_level])

    # Index for owner queries
    create index(:space_objects, [:owner])

    # Index for orbit type
    create index(:space_objects, [:orbit_type])

    # Index for altitude-based queries
    create index(:space_objects, [:apogee_km])
    create index(:space_objects, [:perigee_km])

    # Index for inclination queries
    create index(:space_objects, [:inclination_deg])

    # Index for protected assets
    create index(:space_objects, [:is_protected_asset])

    # Index for stale TLE queries
    create index(:space_objects, [:tle_updated_at])

    # Index for linked satellites
    create index(:space_objects, [:satellite_id])

    # Composite index for orbital regime queries
    create index(:space_objects, [:perigee_km, :apogee_km])
  end
end
