defmodule StellarData.Release do
  @moduledoc """
  Release tasks for database migrations.

  Used by the Kubernetes migration job to run Ecto migrations
  without starting the full application.
  """

  @app :stellar_data

  @doc """
  Run all pending migrations.
  """
  def migrate do
    load_app()

    for repo <- repos() do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end
  end

  @doc """
  Rollback the last migration.
  """
  def rollback(repo, version) do
    load_app()
    {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :down, to: version))
  end

  @doc """
  Print the current migration status.
  """
  def migration_status do
    load_app()

    for repo <- repos() do
      {:ok, result, _} =
        Ecto.Migrator.with_repo(repo, fn repo ->
          Ecto.Migrator.migrations(repo)
        end)

      IO.puts("Migration status for #{inspect(repo)}:")

      for {status, version, name} <- result do
        IO.puts("  #{status}\t#{version}\t#{name}")
      end
    end
  end

  defp repos do
    Application.fetch_env!(@app, :ecto_repos)
  end

  defp load_app do
    Application.load(@app)
  end
end
