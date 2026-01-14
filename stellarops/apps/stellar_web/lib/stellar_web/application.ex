defmodule StellarWeb.Application do
  @moduledoc """
  OTP Application for StellarWeb.

  Starts the Phoenix endpoint and PubSub for real-time communication.
  """

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      # Start the PubSub system
      {Phoenix.PubSub, name: StellarWeb.PubSub},
      # Start the Endpoint (http/https)
      StellarWeb.Endpoint
    ]

    opts = [strategy: :one_for_one, name: StellarWeb.Supervisor]
    Supervisor.start_link(children, opts)
  end

  @impl true
  def config_change(changed, _new, removed) do
    StellarWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
