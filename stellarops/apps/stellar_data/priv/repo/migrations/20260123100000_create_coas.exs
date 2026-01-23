defmodule StellarData.Repo.Migrations.CreateCoas do
  use Ecto.Migration

  def change do
    # TASK-289: Create COAs table
    create table(:coas, primary_key: false) do
      add :id, :binary_id, primary_key: true

      # TASK-291: Foreign key to conjunction
      add :conjunction_id, references(:conjunctions, type: :binary_id, on_delete: :delete_all),
        null: false

      # TASK-292: COA type
      add :type, :string, null: false

      # TASK-293: Basic info
      add :name, :string, null: false
      add :objective, :string
      add :description, :text

      # TASK-294-295: Delta-V parameters
      add :delta_v_magnitude, :float, null: false
      add :delta_v_direction, :map

      # TASK-296-297: Burn timing
      add :burn_start_time, :utc_datetime
      add :burn_duration_seconds, :float

      # TASK-298: Fuel consumption
      add :estimated_fuel_kg, :float

      # TASK-299: Predicted outcome
      add :predicted_miss_distance_km, :float

      # TASK-300: Risk assessment
      add :risk_score, :float

      # TASK-301: Status tracking
      add :status, :string, null: false, default: "proposed"

      # TASK-302-303: Orbital elements
      add :pre_burn_orbit, :map
      add :post_burn_orbit, :map

      # TASK-304: Selection tracking
      add :selected_at, :utc_datetime
      add :selected_by, :string

      # Additional metadata
      add :executed_at, :utc_datetime
      add :completed_at, :utc_datetime
      add :failure_reason, :text

      timestamps(type: :utc_datetime)
    end

    # TASK-305: Index on conjunction_id
    create index(:coas, [:conjunction_id])
    create index(:coas, [:status])
    create index(:coas, [:type])
    create index(:coas, [:risk_score])
  end
end
