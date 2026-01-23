defmodule StellarData.Repo.Migrations.CreateTokenRevocations do
  use Ecto.Migration

  def change do
    create table(:token_revocations, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :jti, :string, null: false
      add :expires_at, :utc_datetime_usec, null: false
      add :revoked_at, :utc_datetime_usec, null: false

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:token_revocations, [:jti])
    create index(:token_revocations, [:expires_at])
  end
end
