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
    []
  end

  defp aliases do
    [
      setup: ["deps.get", "cmd mix setup"],
      test: ["cmd mix test"]
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
