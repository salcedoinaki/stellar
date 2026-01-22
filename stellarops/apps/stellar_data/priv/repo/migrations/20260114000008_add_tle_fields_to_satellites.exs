defmodule StellarData.Repo.Migrations.AddTleFieldsToSatellites do
  use Ecto.Migration

  def change do
    alter table(:satellites) do
      add :norad_id, :string
      add :tle_epoch, :utc_datetime_usec
      add :tle_updated_at, :utc_datetime_usec
    end

    create index(:satellites, [:norad_id], unique: true)
    create index(:satellites, [:tle_updated_at])
    create index(:satellites, [:active, :norad_id])
  end
end
