import Config

# Production environment configuration

# Note: Host configuration comes from runtime.exs PHX_HOST env var
# Secrets should come from runtime.exs or environment variables
config :stellar_web, StellarWeb.Endpoint,
  cache_static_manifest: "priv/static/cache_manifest.json"

config :logger, level: :info

# JSON structured logging for production
config :logger, :console,
  format: {LoggerJSON.Formatters.GoogleCloud, :format},
  metadata: :all

config :logger_json, :backend,
  metadata: :all,
  json_encoder: Jason,
  formatter: LoggerJSON.Formatters.GoogleCloud
