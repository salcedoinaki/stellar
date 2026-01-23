defmodule StellarData.Repo.Migrations.AddCoaIdToMissions do
  use Ecto.Migration

  def change do
    alter table(:missions) do
      add :coa_id, references(:coas, on_delete: :nilify_all, type: :binary_id)
      add :scheduled_start, :utc_datetime
      add :estimated_duration_seconds, :integer
    end

    create index(:missions, [:coa_id])
    create index(:missions, [:scheduled_start])
  end
end
