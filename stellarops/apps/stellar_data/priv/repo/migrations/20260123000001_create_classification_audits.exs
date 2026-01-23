defmodule StellarData.Repo.Migrations.CreateClassificationAudits do
  use Ecto.Migration

  def change do
    create table(:classification_audits, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :space_object_id, references(:space_objects, type: :binary_id, on_delete: :delete_all), null: false
      add :old_classification, :string
      add :new_classification, :string, null: false
      add :old_threat_level, :string
      add :new_threat_level, :string
      add :changed_by, :string
      add :changed_at, :utc_datetime, null: false
      add :reason, :text

      timestamps()
    end

    create index(:classification_audits, [:space_object_id])
    create index(:classification_audits, [:changed_at])
    create index(:classification_audits, [:changed_by])
  end
end
