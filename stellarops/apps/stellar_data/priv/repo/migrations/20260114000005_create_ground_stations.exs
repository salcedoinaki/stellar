defmodule StellarData.Repo.Migrations.CreateGroundStations do
  use Ecto.Migration

  def change do
    create table(:ground_stations, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :code, :string, null: false
      add :description, :text

      # Geographic location
      add :latitude, :float, null: false
      add :longitude, :float, null: false
      add :altitude, :float, null: false, default: 0.0
      add :timezone, :string, null: false, default: "UTC"

      # Capabilities
      add :bandwidth_mbps, :float, null: false, default: 100.0
      add :frequency_band, :string, null: false, default: "S"
      add :min_elevation, :float, null: false, default: 5.0
      add :antenna_diameter, :float

      # Status
      add :status, :string, null: false, default: "online"
      add :current_load, :float, null: false, default: 0.0

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:ground_stations, [:code])
    create index(:ground_stations, [:status])
  end
end
