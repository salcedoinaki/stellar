defmodule StellarData.Repo.Migrations.CreateThreatAssessments do
  use Ecto.Migration

  def change do
    create table(:threat_assessments, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :space_object_id, references(:space_objects, on_delete: :delete_all, type: :binary_id), null: false

      add :classification, :string, default: "unknown", null: false
      add :capabilities, {:array, :string}, default: [], null: false
      add :threat_level, :string, default: "none", null: false
      add :intel_summary, :text
      add :notes, :text
      add :assessed_by, :string
      add :assessed_at, :utc_datetime
      add :confidence_level, :string, default: "low", null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:threat_assessments, [:space_object_id])
    create index(:threat_assessments, [:classification])
    create index(:threat_assessments, [:threat_level])
    create index(:threat_assessments, [:assessed_at])
  end
end
