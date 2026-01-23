defmodule StellarWeb.MixProject do
  use Mix.Project

  def project do
    [
      app: :stellar_web,
      version: "0.1.0",
      build_path: "../../_build",
      config_path: "../../config/config.exs",
      deps_path: "../../deps",
      lockfile: "../../mix.lock",
      elixir: "~> 1.15",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps()
    ]
  end

  def application do
    [
      mod: {StellarWeb.Application, []},
      extra_applications: [:logger, :runtime_tools]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:phoenix, "~> 1.7.14"},
      {:phoenix_pubsub, "~> 2.1"},
      {:jason, "~> 1.4"},
      {:bandit, "~> 1.5"},
      {:cors_plug, "~> 3.0"},
      # Authentication
      {:guardian, "~> 2.3"},
      {:argon2_elixir, "~> 4.0"},
      # Observability - prom_ex with all required optional deps
      {:prom_ex, "~> 1.9"},
      {:finch, "~> 0.18"},
      {:mint, "~> 1.0"},
      {:nimble_pool, "~> 1.0"},
      {:nimble_options, "~> 1.0"},
      {:castore, "~> 1.0"},
      {:telemetry_metrics, "~> 1.0"},
      {:telemetry_poller, "~> 1.0"},
      {:logger_json, "~> 5.1"},
      # Clustering
      {:libcluster, "~> 3.3"},
      # Umbrella dependency
      {:stellar_core, in_umbrella: true}
    ]
  end

  defp aliases do
    [
      setup: ["deps.get"]
    ]
  end
end
