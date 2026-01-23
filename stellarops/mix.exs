defmodule Stellarops.MixProject do
  use Mix.Project

  def project do
    [
      apps_path: "apps",
      version: "0.1.0",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases(),
      releases: releases()
    ]
  end

  defp deps do
    [
      # Build tools (required for native extensions)
      {:elixir_make, "~> 0.8", runtime: false},
      # Development and test dependencies
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false}
    ]
  end

  defp aliases do
    [
      setup: ["deps.get", "cmd mix setup"],
      test: ["cmd mix test"],
      "ci.lint": ["format --check-formatted", "credo --strict"],
      "ci.test": ["test --cover"]
    ]
  end

  defp releases do
    [
      stellarops: [
        version: "0.1.0",
        applications: [
          stellar_core: :permanent,
          stellar_data: :permanent,
          stellar_web: :permanent
        ],
        include_executables_for: [:unix],
        steps: [:assemble, :tar]
      ]
    ]
  end
end
