defmodule StellarData.Repo.Migrations.CreateAlarms do
  use Ecto.Migration

  def change do
    create table(:alarms, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :type, :string, null: false
      add :severity, :string, null: false
      add :message, :text, null: false
      add :source, :string, null: false
      add :details, :map, default: %{}
      add :status, :string, null: false, default: "active"

      # Acknowledgment
      add :acknowledged_at, :utc_datetime_usec
      add :acknowledged_by, :string

      # Resolution
      add :resolved_at, :utc_datetime_usec

      # Optional foreign keys (not enforced for flexibility)
      add :satellite_id, :string
      add :mission_id, :binary_id
      add :ground_station_id, :binary_id

      timestamps(type: :utc_datetime_usec)
    end

    # Indexes for common queries
    create index(:alarms, [:status])
    create index(:alarms, [:severity])
    create index(:alarms, [:type])
    create index(:alarms, [:source])
    create index(:alarms, [:satellite_id])
    create index(:alarms, [:mission_id])
    create index(:alarms, [:status, :severity])
    create index(:alarms, [:inserted_at])

    # Partial index for active alarms (most common query)
    create index(:alarms, [:severity, :inserted_at],
      where: "status = 'active'",
      name: :alarms_active_by_severity
    )

    # Index for cleanup of old resolved alarms
    create index(:alarms, [:resolved_at],
      where: "status = 'resolved'",
      name: :alarms_resolved_for_cleanup
    )
  end
end
