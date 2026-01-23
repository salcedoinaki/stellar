import Config

# Phoenix/JSON configuration
config :phoenix, :json_library, Jason

# StellarWeb endpoint configuration
config :stellar_web, StellarWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [json: StellarWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: StellarWeb.PubSub

# Ecto Repo configuration
config :stellar_data,
  ecto_repos: [StellarData.Repo]

config :stellar_data, StellarData.Repo,
  migration_timestamps: [type: :utc_datetime_usec]

# Logger configuration
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id, :satellite_id]

# Guardian JWT configuration
config :stellar_web, StellarWeb.Auth.Guardian,
  issuer: "stellar_ops",
  secret_key: "development_secret_key_replace_in_production",
  ttl: {1, :hour},
  allowed_drift: 60_000

# PromEx configuration - disable Grafana Agent to avoid OctoFetch dependency
config :stellar_web, StellarWeb.PromEx,
  disabled: false,
  manual_metrics_start_delay: :no_delay,
  drop_metrics_groups: [],
  grafana_agent: :disabled

# Import environment specific config
import_config "#{config_env()}.exs"
