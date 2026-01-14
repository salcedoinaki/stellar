defmodule StellarData.Repo.Migrations.CreateSatellites do
  use Ecto.Migration

  def change do
    create table(:satellites, primary_key: false) do
      add :id, :string, primary_key: true
      add :name, :string
      add :mode, :string, default: "nominal"
      add :energy, :float, default: 100.0
      add :memory_used, :float, default: 0.0
      add :position_x, :float, default: 0.0
      add :position_y, :float, default: 0.0
      add :position_z, :float, default: 0.0
      add :tle_line1, :string
      add :tle_line2, :string
      add :launched_at, :utc_datetime_usec
      add :active, :boolean, default: true

      timestamps(type: :utc_datetime_usec)
    end

    create index(:satellites, [:active])
    create index(:satellites, [:mode])
  end
end
