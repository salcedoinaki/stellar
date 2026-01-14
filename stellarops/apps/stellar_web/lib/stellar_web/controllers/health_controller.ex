defmodule StellarWeb.HealthController do
  @moduledoc """
  Health check endpoint for the API.
  """

  use Phoenix.Controller, formats: [:json]

  @doc """
  GET /health

  Returns the health status of the API and satellite count.
  """
  def index(conn, _params) do
    satellite_count = StellarCore.Satellite.count()

    json(conn, %{
      status: "ok",
      service: "stellar_web",
      satellite_count: satellite_count,
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
    })
  end
end
