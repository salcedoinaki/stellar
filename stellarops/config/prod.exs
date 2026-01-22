import Config

# Production environment configuration

# Note: Host configuration comes from runtime.exs PHX_HOST env var
# Secrets should come from runtime.exs or environment variables
config :stellar_web, StellarWeb.Endpoint,
  cache_static_manifest: "priv/static/cache_manifest.json"

config :logger, level: :info

# JSON structured logging for production
# Uses our custom JSON formatter for compatibility with log aggregation systems
config :logger, :console,
  format: {StellarCore.Logger.JSONFormatter, :format},
  metadata: :all
