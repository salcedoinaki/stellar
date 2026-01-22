defmodule StellarData.Repo.Migrations.CreateUsers do
  use Ecto.Migration

  def change do
    create table(:users, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :email, :string, null: false
      add :password_hash, :string, null: false
      add :name, :string, null: false
      add :role, :string, null: false, default: "viewer"
      add :active, :boolean, null: false, default: true
      add :last_login_at, :utc_datetime_usec
      add :failed_login_attempts, :integer, null: false, default: 0
      add :locked_at, :utc_datetime_usec
      add :metadata, :map, null: false, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:users, [:email])
    create index(:users, [:role])
    create index(:users, [:active])
  end
end
