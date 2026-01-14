defmodule StellarWeb.MissionController do
  @moduledoc """
  REST API controller for mission management.
  """

  use StellarWeb, :controller

  alias StellarData.Missions
  alias StellarCore.Scheduler.MissionScheduler

  action_fallback StellarWeb.FallbackController

  @doc """
  GET /api/missions
  List missions with optional filters.
  """
  def index(conn, params) do
    filters = build_filters(params)
    missions = Missions.list_missions(filters)
    render(conn, :index, missions: missions)
  end

  @doc """
  GET /api/missions/:id
  Get a specific mission.
  """
  def show(conn, %{"id" => id}) do
    case Missions.get_mission(id) do
      nil -> {:error, :not_found}
      mission -> render(conn, :show, mission: mission)
    end
  end

  @doc """
  POST /api/missions
  Create and submit a new mission for scheduling.
  """
  def create(conn, %{"mission" => mission_params}) do
    case MissionScheduler.submit_mission(mission_params) do
      {:ok, mission} ->
        conn
        |> put_status(:created)
        |> render(:show, mission: mission)

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  @doc """
  PATCH /api/missions/:id/cancel
  Cancel a pending or scheduled mission.
  """
  def cancel(conn, %{"id" => id} = params) do
    reason = Map.get(params, "reason", "Canceled via API")

    with mission when not is_nil(mission) <- Missions.get_mission(id),
         {:ok, updated} <- Missions.cancel_mission(mission, reason) do
      render(conn, :show, mission: updated)
    else
      nil -> {:error, :not_found}
      {:error, reason} -> {:error, {:unprocessable_entity, reason}}
    end
  end

  @doc """
  GET /api/missions/stats
  Get mission statistics.
  """
  def stats(conn, _params) do
    scheduler_status = MissionScheduler.status()
    counts = Missions.count_by_status()
    overdue = length(Missions.get_overdue_missions())

    stats = %{
      by_status: counts,
      overdue: overdue,
      scheduler: scheduler_status
    }

    json(conn, stats)
  end

  @doc """
  GET /api/satellites/:satellite_id/missions
  Get missions for a specific satellite.
  """
  def satellite_missions(conn, %{"satellite_id" => satellite_id} = params) do
    opts =
      []
      |> maybe_add_opt(:status, params["status"])
      |> maybe_add_opt(:limit, parse_int(params["limit"]))

    missions = Missions.get_satellite_missions(satellite_id, opts)
    render(conn, :index, missions: missions)
  end

  # ============================================================================
  # Private Helpers
  # ============================================================================

  defp build_filters(params) do
    %{}
    |> maybe_add_filter(:satellite_id, params["satellite_id"])
    |> maybe_add_filter(:status, parse_status(params["status"]))
    |> maybe_add_filter(:priority, parse_priority(params["priority"]))
    |> maybe_add_filter(:type, params["type"])
  end

  defp maybe_add_filter(filters, _key, nil), do: filters
  defp maybe_add_filter(filters, key, value), do: Map.put(filters, key, value)

  defp maybe_add_opt(opts, _key, nil), do: opts
  defp maybe_add_opt(opts, key, value), do: Keyword.put(opts, key, value)

  defp parse_status(nil), do: nil

  defp parse_status(status) when is_binary(status) do
    case status do
      "pending" -> :pending
      "scheduled" -> :scheduled
      "running" -> :running
      "completed" -> :completed
      "failed" -> :failed
      "canceled" -> :canceled
      _ -> nil
    end
  end

  defp parse_priority(nil), do: nil

  defp parse_priority(priority) when is_binary(priority) do
    case priority do
      "critical" -> :critical
      "high" -> :high
      "normal" -> :normal
      "low" -> :low
      _ -> nil
    end
  end

  defp parse_int(nil), do: nil

  defp parse_int(str) when is_binary(str) do
    case Integer.parse(str) do
      {int, _} -> int
      :error -> nil
    end
  end
end
