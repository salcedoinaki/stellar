defmodule StellarWeb.AlarmController do
  @moduledoc """
  Controller for alarm management.
  """

  use StellarWeb, :controller

  alias StellarCore.Alarms

  action_fallback StellarWeb.FallbackController

  @doc """
  Lists all alarms with optional filtering.

  Query params:
  - status: active, acknowledged, resolved
  - severity: critical, major, minor, warning, info
  - source: filter by source prefix (e.g., "satellite:", "mission:")
  - limit: max results (default 100)
  """
  def index(conn, params) do
    opts =
      []
      |> maybe_add_filter(:status, params["status"])
      |> maybe_add_filter(:severity, params["severity"])
      |> maybe_add_filter(:source, params["source"])
      |> maybe_add_limit(params["limit"])

    alarms = Alarms.list_alarms(opts)
    render(conn, :index, alarms: alarms)
  end

  @doc """
  Gets alarm summary (counts by status and severity).
  """
  def summary(conn, _params) do
    summary = Alarms.get_summary()
    render(conn, :summary, summary: summary)
  end

  @doc """
  Gets a specific alarm by ID.
  """
  def show(conn, %{"id" => id}) do
    case Alarms.get_alarm(id) do
      {:ok, alarm} ->
        render(conn, :show, alarm: alarm)

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> put_view(json: StellarWeb.ErrorJSON)
        |> render(:"404")
    end
  end

  @doc """
  Acknowledges an alarm.
  """
  def acknowledge(conn, %{"id" => id} = params) do
    user = params["user"] || "api"

    case Alarms.acknowledge(id, user) do
      :ok ->
        {:ok, alarm} = Alarms.get_alarm(id)
        render(conn, :show, alarm: alarm)

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> put_view(json: StellarWeb.ErrorJSON)
        |> render(:"404")
    end
  end

  @doc """
  Resolves an alarm.
  """
  def resolve(conn, %{"id" => id}) do
    case Alarms.resolve(id) do
      :ok ->
        {:ok, alarm} = Alarms.get_alarm(id)
        render(conn, :show, alarm: alarm)

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> put_view(json: StellarWeb.ErrorJSON)
        |> render(:"404")
    end
  end

  @doc """
  Raises a test alarm (for testing/demo purposes).
  """
  def create(conn, %{"type" => type, "severity" => severity, "message" => message} = params) do
    severity_atom = String.to_existing_atom(severity)
    source = params["source"] || "api:test"
    details = params["details"] || %{}

    {:ok, alarm} = Alarms.raise_alarm(type, severity_atom, message, source, details)

    conn
    |> put_status(:created)
    |> render(:show, alarm: alarm)
  rescue
    ArgumentError ->
      conn
      |> put_status(:bad_request)
      |> put_view(json: StellarWeb.ErrorJSON)
      |> render(:"400")
  end

  @doc """
  Clears old resolved alarms.
  """
  def clear_resolved(conn, params) do
    older_than = String.to_integer(params["older_than_seconds"] || "86400")
    {:ok, count} = Alarms.clear_resolved(older_than)
    json(conn, %{cleared: count})
  end

  # Private helpers

  defp maybe_add_filter(opts, _key, nil), do: opts
  defp maybe_add_filter(opts, _key, ""), do: opts

  defp maybe_add_filter(opts, :status, value) do
    Keyword.put(opts, :status, String.to_existing_atom(value))
  rescue
    ArgumentError -> opts
  end

  defp maybe_add_filter(opts, :severity, value) do
    Keyword.put(opts, :severity, String.to_existing_atom(value))
  rescue
    ArgumentError -> opts
  end

  defp maybe_add_filter(opts, :source, value) do
    Keyword.put(opts, :source, value)
  end

  defp maybe_add_limit(opts, nil), do: opts
  defp maybe_add_limit(opts, ""), do: opts

  defp maybe_add_limit(opts, value) do
    Keyword.put(opts, :limit, String.to_integer(value))
  rescue
    ArgumentError -> opts
  end
end
