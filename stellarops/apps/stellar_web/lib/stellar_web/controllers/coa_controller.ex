defmodule StellarWeb.COAController do
  @moduledoc """
  REST API controller for Course of Action recommendations.

  Provides endpoints for:
  - Listing COAs
  - Viewing COA details
  - Approving/Rejecting COAs
  - Triggering COA generation
  - Maneuver planning
  """

  use StellarWeb, :controller

  alias StellarData.COA
  alias StellarCore.SSA.COAPlanner

  action_fallback StellarWeb.FallbackController

  @doc """
  List COAs with optional filtering.
  """
  def index(conn, params) do
    opts = build_query_opts(params)
    coas = COA.list_coas(opts)
    render(conn, :index, coas: coas)
  end

  @doc """
  Get pending COAs requiring decision.
  """
  def pending(conn, _params) do
    coas = COA.list_pending_coas()
    render(conn, :index, coas: coas)
  end

  @doc """
  Get urgent COAs with approaching deadlines.
  """
  def urgent(conn, params) do
    hours = parse_integer(params["hours"], 24)
    coas = COA.list_urgent_coas(hours)
    render(conn, :index, coas: coas)
  end

  @doc """
  Get a specific COA by ID.
  """
  def show(conn, %{"id" => id}) do
    case COA.get_coa(id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Course of action not found"})

      coa ->
        render(conn, :show, coa: coa)
    end
  end

  @doc """
  Get COAs for a specific satellite.
  """
  def for_satellite(conn, %{"satellite_id" => satellite_id} = params) do
    opts = [limit: parse_integer(params["limit"], 50)]
    coas = COA.list_coas_for_satellite(satellite_id, opts)
    render(conn, :index, coas: coas)
  end

  @doc """
  Get COAs for a specific conjunction.
  """
  def for_conjunction(conn, %{"conjunction_id" => conjunction_id}) do
    coas = COA.list_coas_for_conjunction(conjunction_id)
    render(conn, :index, coas: coas)
  end

  @doc """
  Get recommended COA for a conjunction.
  """
  def recommended(conn, %{"conjunction_id" => conjunction_id}) do
    case COA.get_recommended_coa(conjunction_id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "No recommendation found for this conjunction"})

      coa ->
        render(conn, :show, coa: coa)
    end
  end

  @doc """
  Approve a COA.
  """
  def approve(conn, %{"id" => id} = params) do
    approved_by = params["approved_by"] || "operator"
    notes = params["notes"]

    case COA.get_coa(id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Course of action not found"})

      coa ->
        case COA.approve_coa(coa, approved_by, notes) do
          {:ok, updated} ->
            broadcast_decision(updated, "approved")
            render(conn, :show, coa: updated)

          {:error, changeset} ->
            conn
            |> put_status(:unprocessable_entity)
            |> json(%{error: format_errors(changeset)})
        end
    end
  end

  @doc """
  Reject a COA.
  """
  def reject(conn, %{"id" => id} = params) do
    rejected_by = params["rejected_by"] || "operator"
    notes = params["notes"]

    case COA.get_coa(id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Course of action not found"})

      coa ->
        case COA.reject_coa(coa, rejected_by, notes) do
          {:ok, updated} ->
            broadcast_decision(updated, "rejected")
            render(conn, :show, coa: updated)

          {:error, changeset} ->
            conn
            |> put_status(:unprocessable_entity)
            |> json(%{error: format_errors(changeset)})
        end
    end
  end

  @doc """
  Generate COAs for a conjunction.
  """
  def generate(conn, %{"conjunction_id" => conjunction_id}) do
    case COAPlanner.generate_coas(conjunction_id) do
      {:ok, coas} ->
        conn
        |> put_status(:created)
        |> render(:index, coas: coas)

      {:error, :conjunction_not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Conjunction not found"})

      {:error, reason} ->
        conn
        |> put_status(:internal_server_error)
        |> json(%{error: inspect(reason)})
    end
  end

  @doc """
  Plan a maneuver for a conjunction.
  """
  def plan_maneuver(conn, %{"conjunction_id" => conjunction_id} = params) do
    opts = [
      lead_hours: parse_integer(params["lead_hours"], 24),
      direction: parse_atom(params["direction"]) || :posigrade
    ]

    case COAPlanner.plan_maneuver(conjunction_id, opts) do
      {:ok, maneuver} ->
        json(conn, %{data: maneuver})

      {:error, :conjunction_not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Conjunction not found"})

      {:error, reason} ->
        conn
        |> put_status(:internal_server_error)
        |> json(%{error: inspect(reason)})
    end
  end

  @doc """
  Get COA counts by status.
  """
  def status_counts(conn, _params) do
    counts = COA.count_by_status()
    json(conn, %{data: counts})
  end

  @doc """
  Get planner status.
  """
  def planner_status(conn, _params) do
    status = COAPlanner.get_status()
    json(conn, %{data: status})
  end

  # Private helpers

  defp build_query_opts(params) do
    [
      satellite_id: params["satellite_id"],
      status: parse_atom(params["status"]),
      coa_type: parse_atom(params["coa_type"]),
      priority: parse_atom(params["priority"]),
      limit: parse_integer(params["limit"], 50)
    ]
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
  end

  defp parse_integer(nil, default), do: default
  defp parse_integer(str, default) do
    case Integer.parse(str) do
      {n, _} -> n
      :error -> default
    end
  end

  defp parse_atom(nil), do: nil
  defp parse_atom(str) when is_binary(str) do
    String.to_existing_atom(str)
  rescue
    ArgumentError -> nil
  end

  defp format_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
  end

  defp broadcast_decision(coa, action) do
    Phoenix.PubSub.broadcast(
      StellarCore.PubSub,
      "ssa:coa",
      {:coa_decision, %{
        coa_id: coa.id,
        action: action,
        decided_by: coa.decided_by
      }}
    )
  end
end
