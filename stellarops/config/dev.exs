import Config

# Development environment configuration

# StellarWeb endpoint (dev)
config :stellar_web, StellarWeb.Endpoint,
  http: [ip: {0, 0, 0, 0}, port: 4000],
  check_origin: false,
  code_reloader: true,
  debug_errors: true,
  secret_key_base: "dev-secret-key-base-that-is-at-least-64-bytes-long-for-development-only",
  watchers: []

# StellarData Postgres (dev)
# Use DATABASE_HOSTNAME env var for flexibility between Docker and local dev
config :stellar_data, StellarData.Repo,
  username: System.get_env("DATABASE_USERNAME", "postgres"),
  password: System.get_env("DATABASE_PASSWORD", "postgres"),
  hostname: System.get_env("DATABASE_HOSTNAME", "localhost"),
  database: System.get_env("DATABASE_NAME", "stellar_dev"),
  stacktrace: true,
  show_sensitive_data_on_connection_error: true,
  pool_size: 10

# Logger - default to :info for clean console, use CLI.debug(true) for debug output
config :logger, :console,
  format: "[$level] $message\n",
  level: :info

# Allow anonymous WebSocket connections in development
config :stellar_web, :allow_anonymous_websocket, true
