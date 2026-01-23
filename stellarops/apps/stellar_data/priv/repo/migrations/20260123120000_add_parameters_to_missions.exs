defmodule StellarData.Repo.Migrations.AddParametersToMissions do
  use Ecto.Migration

  def change do
    alter table(:missions) do
      add :parameters, :map, default: %{}
    end
  end
end
