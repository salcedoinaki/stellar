defmodule StellarData.Repo do
  use Ecto.Repo,
    otp_app: :stellar_data,
    adapter: Ecto.Adapters.Postgres
end
