import Config

# Test environment configuration

# StellarWeb endpoint (test)
config :stellar_web, StellarWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "test-secret-key-base-that-is-at-least-64-bytes-long-for-testing-only-ok",
  server: false

# StellarData Postgres (test)
# Use async sandbox for concurrent tests
config :stellar_data, StellarData.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "db",
  database: "stellar_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

# Logger - only warnings and above during tests
config :logger, level: :warning
