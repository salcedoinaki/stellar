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

# Import environment specific config
import_config "#{config_env()}.exs"
