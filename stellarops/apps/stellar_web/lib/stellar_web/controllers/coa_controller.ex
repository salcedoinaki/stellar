defmodule StellarWeb.COAController do
  @moduledoc """
  REST API controller for Course of Action recommendations.

  Provides endpoints for:
  - Listing COAs (by conjunction or satellite)
  - Viewing COA details
  - Selecting/Approving/Rejecting COAs
  - Triggering COA generation and regeneration
  - Simulation and maneuver planning
  """

  use StellarWeb, :controller

  alias StellarData.COAs
  alias StellarData.Conjunctions
  alias StellarCore.SSA.COAPlanner
  alias StellarCore.COAExecutor

  action_fallback StellarWeb.FallbackController

  # ============================================================================
  # List and Show
  # ============================================================================

  @doc """
  List COAs with optional filtering.

  GET /api/coas
  """
  def index(conn, params) do
    opts = build_query_opts(params)
    coas = COAs.list_coas(opts)
    render(conn, :index, coas: coas)
  end

  @doc """
  Get pending COAs requiring decision.

  GET /api/coas/pending
  """
  def pending(conn, _params) do
    coas = COAs.list_pending_coas()
    render(conn, :index, coas: coas)
  end

  @doc """
  Get urgent COAs with approaching deadlines.

  GET /api/coas/urgent
  """
  def urgent(conn, params) do
    hours = parse_integer(params["hours"], 24)
    coas = COAs.list_urgent_coas(hours)
    render(conn, :index, coas: coas)
  end

  @doc """
  Get a specific COA by ID.

  GET /api/coas/:id

  Includes conjunction details and execution status.
  """
  def show(conn, %{"id" => id}) do
    case COAs.get_coa_with_conjunction(id) do
      nil ->
        {:error, :not_found}

      coa ->
        execution_status = COAExecutor.get_execution_status(id)
        render(conn, :show, coa: coa, execution_status: execution_status)
    end
  end

  @doc """
  Get COAs for a specific satellite.

  GET /api/satellites/:satellite_id/coas
  """
  def for_satellite(conn, %{"satellite_id" => satellite_id} = params) do
    opts = [limit: parse_integer(params["limit"], 50)]
    coas = COAs.list_coas_for_satellite(satellite_id, opts)
    render(conn, :index, coas: coas)
  end

  @doc """
  Get COAs for a specific conjunction.

  GET /api/conjunctions/:conjunction_id/coas
  """
  def for_conjunction(conn, %{"conjunction_id" => conjunction_id}) do
    with {:ok, _conjunction} <- get_conjunction(conjunction_id) do
      coas = COAs.list_coas_for_conjunction(conjunction_id)
      render(conn, :index, coas: coas)
    end
  end

  @doc """
  Get recommended COA for a conjunction.

  GET /api/conjunctions/:conjunction_id/coas/recommended
  """
  def recommended(conn, %{"conjunction_id" => conjunction_id}) do
    case COAs.get_recommended_coa(conjunction_id) do
      nil ->
        {:error, :not_found}

      coa ->
        render(conn, :show, coa: coa, execution_status: nil)
    end
  end

  # ============================================================================
  # COA Decisions
  # ============================================================================

  @doc """
  Selects a COA for execution.

  POST /api/coas/:id/select

  This marks the COA as selected, rejects other proposed COAs,
  and triggers mission creation.
  """
  def select(conn, %{"id" => id} = params) do
    selected_by = Map.get(params, "selected_by", "operator")

    with coa when not is_nil(coa) <- COAs.get_coa(id),
         :ok <- validate_selectable(coa),
         {:ok, selected_coa} <- COAs.select_coa(coa, selected_by),
         {:ok, execution_result} <- COAExecutor.execute_coa(selected_coa) do

      broadcast_decision(selected_coa, "selected")

      conn
      |> put_status(:ok)
      |> render(:select, coa: execution_result.coa, missions: execution_result.missions)
    else
      nil -> {:error, :not_found}
      {:error, :not_selectable} -> {:error, :bad_request, "COA is not in proposed status"}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Approve a COA.

  POST /api/coas/:id/approve
  """
  def approve(conn, %{"id" => id} = params) do
    approved_by = params["approved_by"] || "operator"
    notes = params["notes"]

    with coa when not is_nil(coa) <- COAs.get_coa(id),
         {:ok, updated} <- COAs.approve_coa(coa, approved_by, notes) do

      broadcast_decision(updated, "approved")
      render(conn, :show, coa: updated, execution_status: nil)
    else
      nil -> {:error, :not_found}
      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: format_errors(changeset)})
    end
  end

  @doc """
  Reject a COA.

  POST /api/coas/:id/reject
  """
  def reject(conn, %{"id" => id} = params) do
    rejected_by = params["rejected_by"] || "operator"
    notes = params["notes"]

    with coa when not is_nil(coa) <- COAs.get_coa(id),
         :ok <- validate_rejectable(coa),
         {:ok, updated} <- COAs.reject_coa(coa, rejected_by, notes) do

      broadcast_decision(updated, "rejected")
      render(conn, :show, coa: updated, execution_status: nil)
    else
      nil -> {:error, :not_found}
      {:error, :not_rejectable} -> {:error, :bad_request, "COA cannot be rejected in current status"}
      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: format_errors(changeset)})
    end
  end

  # ============================================================================
  # Generation and Simulation
  # ============================================================================

  @doc """
  Generate COAs for a conjunction.

  POST /api/conjunctions/:conjunction_id/coas/generate
  """
  def generate(conn, %{"conjunction_id" => conjunction_id}) do
    with {:ok, _conjunction} <- get_conjunction(conjunction_id),
         {:ok, coas} <- COAPlanner.generate_coas(conjunction_id) do

      conn
      |> put_status(:created)
      |> render(:index, coas: coas)
    end
  end

  @doc """
  Regenerates COAs for a conjunction.

  POST /api/conjunctions/:conjunction_id/coas/regenerate

  Deletes proposed COAs and generates new ones based on current conditions.
  """
  def regenerate(conn, %{"conjunction_id" => conjunction_id}) do
    with {:ok, _conjunction} <- get_conjunction(conjunction_id),
         {:ok, coas} <- COAPlanner.generate_coas(conjunction_id) do

      conn
      |> put_status(:ok)
      |> render(:index, coas: coas)
    end
  end

  @doc """
  Simulates a COA execution and returns predicted outcomes.

  POST /api/coas/:id/simulate

  Returns predicted trajectory after maneuver and miss distance improvement.
  """
  def simulate(conn, %{"id" => id}) do
    with coa when not is_nil(coa) <- COAs.get_coa_with_conjunction(id) do
      trajectory = simulate_post_burn_trajectory(coa)

      original_miss = coa.conjunction.miss_distance_km
      predicted_miss = coa.predicted_miss_distance_km
      improvement = predicted_miss - original_miss
      improvement_percent = if original_miss > 0, do: improvement / original_miss * 100, else: 0

      simulation_result = %{
        coa_id: coa.id,
        coa_type: coa.type,
        original_miss_distance_km: original_miss,
        predicted_miss_distance_km: predicted_miss,
        miss_distance_improvement_km: improvement,
        miss_distance_improvement_percent: Float.round(improvement_percent, 2),
        delta_v_magnitude: coa.delta_v_magnitude,
        fuel_consumption_kg: coa.estimated_fuel_kg,
        burn_duration_seconds: coa.burn_duration_seconds,
        trajectory_points: trajectory,
        pre_burn_orbit: coa.pre_burn_orbit,
        post_burn_orbit: coa.post_burn_orbit
      }

      conn
      |> put_status(:ok)
      |> json(%{data: simulation_result})
    else
      nil -> {:error, :not_found}
    end
  end

  @doc """
  Plan a maneuver for a conjunction.

  POST /api/conjunctions/:conjunction_id/maneuver
  """
  def plan_maneuver(conn, %{"conjunction_id" => conjunction_id} = params) do
    opts = [
      lead_hours: parse_integer(params["lead_hours"], 24),
      direction: parse_atom(params["direction"]) || :posigrade
    ]

    with {:ok, _conjunction} <- get_conjunction(conjunction_id),
         {:ok, maneuver} <- COAPlanner.plan_maneuver(conjunction_id, opts) do
      json(conn, %{data: maneuver})
    end
  end

  # ============================================================================
  # Status and Statistics
  # ============================================================================

  @doc """
  Get COA counts by status.

  GET /api/coas/stats
  """
  def status_counts(conn, _params) do
    counts = COAs.count_by_status()
    json(conn, %{data: counts})
  end

  @doc """
  Get planner status.

  GET /api/coas/planner_status
  """
  def planner_status(conn, _params) do
    status = COAPlanner.get_status()
    json(conn, %{data: status})
  end

  # ============================================================================
  # Private Helpers
  # ============================================================================

  defp get_conjunction(id) do
    case Conjunctions.get_conjunction(id) do
      nil -> {:error, :not_found}
      conjunction -> {:ok, conjunction}
    end
  end

  defp validate_selectable(%{status: :proposed}), do: :ok
  defp validate_selectable(_), do: {:error, :not_selectable}

  defp validate_rejectable(%{status: status}) when status in [:proposed, :selected], do: :ok
  defp validate_rejectable(_), do: {:error, :not_rejectable}

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
      StellarWeb.PubSub,
      "coa:updates",
      {:coa_decision, %{
        coa_id: coa.id,
        action: action,
        decided_by: Map.get(coa, :decided_by) || Map.get(coa, :selected_by)
      }}
    )
  end

  defp simulate_post_burn_trajectory(coa) do
    burn_time = coa.burn_start_time || DateTime.utc_now()
    post_burn_time = DateTime.add(burn_time, round(coa.burn_duration_seconds || 0) + 60, :second)

    # Generate 10 points over 1 orbit (~90 minutes for LEO)
    Enum.map(0..9, fn i ->
      time = DateTime.add(post_burn_time, i * 540, :second)

      # Simulated position based on simplified orbital motion
      angle = i * 0.628  # ~36 degrees per step
      radius = 6771.0 + i * 0.1  # Slight variation

      %{
        timestamp: time,
        position: %{
          x_km: Float.round(radius * :math.cos(angle), 3),
          y_km: Float.round(radius * :math.sin(angle), 3),
          z_km: Float.round(radius * 0.1 * :math.sin(angle * 2), 3)
        },
        altitude_km: Float.round(radius - 6371.0, 2)
      }
    end)
  end
end
