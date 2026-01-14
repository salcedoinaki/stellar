defmodule StellarData.Application do
  @moduledoc """
  OTP Application for StellarData.

  Starts the Ecto Repo for database connections.
  """

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      StellarData.Repo
    ]

    opts = [strategy: :one_for_one, name: StellarData.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
