defmodule StellarData.Repo.Migrations.AddPositionsToConjunctions do
  @moduledoc """
  Add position data at TCA for primary and secondary objects.
  
  These fields store the predicted ECI (Earth-Centered Inertial) positions
  of both objects at the Time of Closest Approach, enabling visualization
  and analysis in the frontend.
  """
  use Ecto.Migration

  def change do
    alter table(:conjunctions) do
      # Primary object (asset) position at TCA in ECI coordinates (km)
      add :primary_position_x_km, :float
      add :primary_position_y_km, :float
      add :primary_position_z_km, :float
      
      # Secondary object position at TCA in ECI coordinates (km)
      add :secondary_position_x_km, :float
      add :secondary_position_y_km, :float
      add :secondary_position_z_km, :float
    end
  end
end
