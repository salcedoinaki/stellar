defmodule StellarData.Repo.Migrations.CreateConjunctions do
  use Ecto.Migration

  def change do
    create table(:conjunctions, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :asset_id, :binary_id, null: false
      add :object_id, references(:space_objects, on_delete: :delete_all, type: :binary_id), null: false

      # Conjunction metrics
      add :tca, :utc_datetime, null: false
      add :miss_distance_km, :float, null: false
      add :relative_velocity_km_s, :float
      add :probability_of_collision, :float

      # Classification
      add :severity, :string, null: false
      add :status, :string, default: "active", null: false

      # Positions at TCA (JSON)
      add :asset_position_at_tca, :map
      add :object_position_at_tca, :map

      # Covariance data for uncertainty
      add :covariance_data, :map

      timestamps(type: :utc_datetime)
    end

    create index(:conjunctions, [:asset_id])
    create index(:conjunctions, [:object_id])
    create index(:conjunctions, [:tca])
    create index(:conjunctions, [:severity])
    create index(:conjunctions, [:status])
    create index(:conjunctions, [:asset_id, :tca])
    create index(:conjunctions, [:asset_id, :status])
  end
end
