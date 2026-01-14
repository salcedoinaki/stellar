defmodule StellarData.Repo.Migrations.CreateTelemetryEvents do
  use Ecto.Migration

  def change do
    create table(:telemetry_events) do
      add :satellite_id, references(:satellites, type: :string, on_delete: :delete_all), null: false
      add :event_type, :string, null: false
      add :data, :map, default: %{}
      add :recorded_at, :utc_datetime_usec, null: false

      timestamps(type: :utc_datetime_usec)
    end

    create index(:telemetry_events, [:satellite_id])
    create index(:telemetry_events, [:satellite_id, :event_type])
    create index(:telemetry_events, [:recorded_at])
  end
end
