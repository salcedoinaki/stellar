defmodule StellarWeb.COAController do
  @moduledoc """
  Controller for Course of Action (COA) management.

  Provides endpoints for listing, viewing, selecting, and simulating COAs
  associated with conjunction events.
  """

  use StellarWeb, :controller

  alias StellarData.COAs
  alias StellarData.Conjunctions
  alias StellarCore.COAPlanner
  alias StellarCore.COAExecutor

  action_fallback StellarWeb.FallbackController

  # TASK-358: List COAs for a conjunction
  @doc """
  Lists all COAs for a specific conjunction.

  GET /api/conjunctions/:conjunction_id/coas
  """
  def index(conn, %{"conjunction_id" => conjunction_id}) do
    with {:ok, _conjunction} <- get_conjunction(conjunction_id) do
      coas = COAs.list_coas_for_conjunction(conjunction_id)

      conn
      |> put_status(:ok)
      |> render(:index, coas: coas)
    end
  end

  # TASK-359-361: Show COA details
  @doc """
  Shows detailed information about a specific COA.

  GET /api/coas/:id

  Includes conjunction details and linked missions.
  """
  def show(conn, %{"id" => id}) do
    case COAs.get_coa_with_conjunction(id) do
      nil ->
        {:error, :not_found}

      coa ->
        # TASK-361: Get linked missions
        execution_status = COAExecutor.get_execution_status(id)

        conn
        |> put_status(:ok)
        |> render(:show, coa: coa, execution_status: execution_status)
    end
  end

  # TASK-362-365: Select a COA
  @doc """
  Selects a COA for execution.

  POST /api/coas/:id/select

  This marks the COA as selected, rejects other proposed COAs,
  and triggers mission creation.
  """
  def select(conn, %{"id" => id} = params) do
    selected_by = Map.get(params, "selected_by", "operator")

    with coa when not is_nil(coa) <- COAs.get_coa(id),
         # TASK-363: Validate COA is in proposed status
         :ok <- validate_selectable(coa),
         # TASK-364: Select COA (rejects others automatically)
         {:ok, selected_coa} <- COAs.select_coa(coa, selected_by),
         # TASK-365: Trigger mission creation
         {:ok, execution_result} <- COAExecutor.execute_coa(selected_coa) do

      # Broadcast update
      Phoenix.PubSub.broadcast(
        StellarWeb.PubSub,
        "coa:updates",
        {:coa_selected, selected_coa.id}
      )

      conn
      |> put_status(:ok)
      |> render(:select, coa: execution_result.coa, missions: execution_result.missions)
    else
      nil -> {:error, :not_found}
      {:error, :not_selectable} -> {:error, :bad_request, "COA is not in proposed status"}
      {:error, reason} -> {:error, reason}
    end
  end

  # TASK-366-368: Simulate a COA
  @doc """
  Simulates a COA execution and returns predicted outcomes.

  POST /api/coas/:id/simulate

  Returns predicted trajectory after maneuver and miss distance improvement.
  """
  def simulate(conn, %{"id" => id}) do
    with coa when not is_nil(coa) <- COAs.get_coa_with_conjunction(id) do
      # TASK-367: Predicted trajectory
      trajectory = simulate_post_burn_trajectory(coa)

      # TASK-368: Miss distance improvement
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

  # TASK-369: Regenerate COAs
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
  Generates initial COAs for a conjunction.

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
  Rejects a COA.

  POST /api/coas/:id/reject
  """
  def reject(conn, %{"id" => id}) do
    with coa when not is_nil(coa) <- COAs.get_coa(id),
         :ok <- validate_rejectable(coa),
         {:ok, rejected_coa} <- COAs.reject_coa(coa) do

      conn
      |> put_status(:ok)
      |> render(:show, coa: rejected_coa, execution_status: nil)
    else
      nil -> {:error, :not_found}
      {:error, :not_rejectable} -> {:error, :bad_request, "COA cannot be rejected in current status"}
      {:error, reason} -> {:error, reason}
    end
  end

  # Private helpers

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

  defp simulate_post_burn_trajectory(coa) do
    # Generate simulated trajectory points after maneuver
    # In production, this would call the orbital propagation service

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
