defmodule StellarData.Repo.Migrations.CreateSpaceObjects do
  use Ecto.Migration

  def change do
    create table(:space_objects, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :norad_id, :integer, null: false
      add :name, :string, null: false
      add :international_designator, :string
      add :object_type, :string, default: "unknown", null: false
      add :owner, :string
      add :country_code, :string
      add :launch_date, :date
      add :orbital_status, :string, default: "unknown", null: false

      # TLE data
      add :tle_line1, :text
      add :tle_line2, :text
      add :tle_epoch, :utc_datetime

      # Derived orbital parameters
      add :apogee_km, :float
      add :perigee_km, :float
      add :inclination_deg, :float
      add :period_min, :float
      add :rcs_meters, :float

      # Metadata
      add :notes, :text

      timestamps(type: :utc_datetime)
    end

    create unique_index(:space_objects, [:norad_id])
    create index(:space_objects, [:object_type])
    create index(:space_objects, [:orbital_status])
    create index(:space_objects, [:name])
  end
end
