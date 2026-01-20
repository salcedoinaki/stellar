defmodule StellarWeb.PromEx do
  @moduledoc """
  PromEx configuration for StellarOps metrics.
  
  Exposes Prometheus metrics at /metrics endpoint.
  """

  use PromEx, otp_app: :stellar_web

  alias PromEx.Plugins

  @impl true
  def plugins do
    [
      # Built-in plugins
      Plugins.Application,
      Plugins.Beam,
      {Plugins.Phoenix, router: StellarWeb.Router, endpoint: StellarWeb.Endpoint},
      {Plugins.Ecto, repos: [StellarData.Repo]},
      
      # Custom StellarOps metrics plugin
      StellarWeb.PromEx.StellarPlugin
    ]
  end

  @impl true
  def dashboard_assigns do
    [
      datasource_id: "prometheus",
      default_selected_interval: "30s"
    ]
  end

  @impl true
  def dashboards do
    [
      # Built-in Grafana dashboards
      {:prom_ex, "application.json"},
      {:prom_ex, "beam.json"},
      {:prom_ex, "phoenix.json"},
      {:prom_ex, "ecto.json"}
    ]
  end
end
