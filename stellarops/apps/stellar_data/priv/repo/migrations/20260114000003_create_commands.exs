defmodule StellarData.Repo.Migrations.CreateCommands do
  use Ecto.Migration

  def change do
    create table(:commands) do
      add :satellite_id, references(:satellites, type: :string, on_delete: :delete_all), null: false
      add :command_type, :string, null: false
      add :params, :map, default: %{}
      add :status, :string, default: "pending"
      add :priority, :integer, default: 0
      add :scheduled_at, :utc_datetime_usec
      add :started_at, :utc_datetime_usec
      add :completed_at, :utc_datetime_usec
      add :result, :map
      add :error_message, :text

      timestamps(type: :utc_datetime_usec)
    end

    create index(:commands, [:satellite_id])
    create index(:commands, [:satellite_id, :status])
    create index(:commands, [:status, :priority])
    create index(:commands, [:scheduled_at])
  end
end
