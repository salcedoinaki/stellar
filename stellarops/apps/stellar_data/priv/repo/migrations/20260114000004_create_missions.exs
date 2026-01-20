defmodule StellarData.Repo.Migrations.CreateMissions do
  use Ecto.Migration

  def change do
    create table(:missions, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :description, :text
      add :type, :string, null: false

      # Scheduling
      add :priority, :string, null: false, default: "normal"
      add :deadline, :utc_datetime_usec
      add :scheduled_at, :utc_datetime_usec
      add :started_at, :utc_datetime_usec
      add :completed_at, :utc_datetime_usec

      # Lifecycle
      add :status, :string, null: false, default: "pending"

      # Retry logic
      add :retry_count, :integer, null: false, default: 0
      add :max_retries, :integer, null: false, default: 3
      add :next_retry_at, :utc_datetime_usec
      add :last_error, :text

      # Resource requirements
      add :required_energy, :float, null: false, default: 10.0
      add :required_memory, :float, null: false, default: 5.0
      add :required_bandwidth, :float, null: false, default: 1.0
      add :estimated_duration, :integer, null: false, default: 300

      # Payload
      add :payload, :map, default: %{}
      add :result, :map

      # Relationships
      add :satellite_id, :string, null: false
      add :ground_station_id, :binary_id

      timestamps(type: :utc_datetime_usec)
    end

    # Indexes for common queries
    create index(:missions, [:satellite_id])
    create index(:missions, [:status])
    create index(:missions, [:priority])
    create index(:missions, [:deadline])
    create index(:missions, [:status, :priority])
    create index(:missions, [:satellite_id, :status])
    create index(:missions, [:next_retry_at], where: "status = 'pending' AND retry_count > 0")
  end
end
