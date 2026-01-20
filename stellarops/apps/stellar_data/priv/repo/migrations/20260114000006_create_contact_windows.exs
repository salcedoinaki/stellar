defmodule StellarData.Repo.Migrations.CreateContactWindows do
  use Ecto.Migration

  def change do
    create table(:contact_windows, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :satellite_id, :string, null: false

      # Time window
      add :aos, :utc_datetime_usec, null: false  # Acquisition of Signal
      add :los, :utc_datetime_usec, null: false  # Loss of Signal
      add :tca, :utc_datetime_usec               # Time of Closest Approach

      # Pass characteristics
      add :max_elevation, :float
      add :aos_azimuth, :float
      add :los_azimuth, :float
      add :duration_seconds, :integer

      # Capacity allocation
      add :allocated_bandwidth, :float, null: false, default: 0.0
      add :data_transferred, :float, null: false, default: 0.0

      # Status
      add :status, :string, null: false, default: "scheduled"

      add :ground_station_id, references(:ground_stations, type: :binary_id, on_delete: :delete_all),
        null: false

      timestamps(type: :utc_datetime_usec)
    end

    create index(:contact_windows, [:satellite_id])
    create index(:contact_windows, [:ground_station_id])
    create index(:contact_windows, [:aos])
    create index(:contact_windows, [:status])
    create index(:contact_windows, [:satellite_id, :aos])
    create index(:contact_windows, [:ground_station_id, :aos, :los])
  end
end
