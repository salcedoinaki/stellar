defmodule StellarWeb.SatelliteController do
  @moduledoc """
  REST API controller for satellite management.

  Provides endpoints to:
  - List all satellites
  - Get individual satellite state
  - Create/spawn new satellites
  - Delete/stop satellites
  - Update satellite parameters
  """

  use Phoenix.Controller, formats: [:json]

  alias StellarCore.Satellite

  action_fallback StellarWeb.FallbackController

  @doc """
  GET /api/satellites

  Returns a list of all active satellites with their states.
  """
  def index(conn, _params) do
    satellites =
      Satellite.list_states()
      |> Enum.map(&serialize_state/1)

    json(conn, %{data: satellites})
  end

  @doc """
  GET /api/satellites/:id

  Returns the state of a specific satellite.
  """
  def show(conn, %{"id" => id}) do
    case Satellite.fetch_state(id) do
      {:ok, state} ->
        json(conn, %{data: serialize_state(state)})

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Satellite not found", id: id})
    end
  end

  @doc """
  POST /api/satellites

  Creates/spawns a new satellite.

  Body: {"id": "SAT-001"} or {} for auto-generated ID
  """
  def create(conn, params) do
    id = Map.get(params, "id", generate_id())

    case Satellite.start(id) do
      {:ok, _pid} ->
        # Broadcast the creation
        StellarWeb.Endpoint.broadcast("satellites:lobby", "satellite_created", %{id: id})

        {:ok, state} = Satellite.get_state(id)

        conn
        |> put_status(:created)
        |> json(%{data: serialize_state(state)})

      {:error, :already_exists} ->
        conn
        |> put_status(:conflict)
        |> json(%{error: "Satellite already exists", id: id})

      {:error, reason} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "Failed to create satellite", reason: inspect(reason)})
    end
  end

  @doc """
  DELETE /api/satellites/:id

  Stops and removes a satellite.
  """
  def delete(conn, %{"id" => id}) do
    case Satellite.stop(id) do
      :ok ->
        # Broadcast the deletion
        StellarWeb.Endpoint.broadcast("satellites:lobby", "satellite_deleted", %{id: id})

        conn
        |> put_status(:ok)
        |> json(%{message: "Satellite stopped", id: id})

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Satellite not found", id: id})
    end
  end

  @doc """
  PUT /api/satellites/:id/energy

  Updates a satellite's energy.

  Body: {"delta": -10.0}
  """
  def update_energy(conn, %{"id" => id, "delta" => delta}) when is_number(delta) do
    case Satellite.update_energy(id, delta) do
      {:ok, state} ->
        # Broadcast the update
        StellarWeb.Endpoint.broadcast("satellites:lobby", "satellite_updated", serialize_state(state))

        json(conn, %{data: serialize_state(state)})

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Satellite not found", id: id})
    end
  end

  def update_energy(conn, %{"id" => _id}) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "Missing or invalid 'delta' parameter"})
  end

  @doc """
  PUT /api/satellites/:id/mode

  Sets a satellite's operational mode.

  Body: {"mode": "safe"} (nominal, safe, or survival)
  """
  def update_mode(conn, %{"id" => id, "mode" => mode_str}) do
    mode = parse_mode(mode_str)

    cond do
      mode == nil ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "Invalid mode. Must be: nominal, safe, or survival"})

      true ->
        case Satellite.set_mode(id, mode) do
          {:ok, state} ->
            # Broadcast the update
            StellarWeb.Endpoint.broadcast("satellites:lobby", "satellite_updated", serialize_state(state))

            json(conn, %{data: serialize_state(state)})

          {:error, :not_found} ->
            conn
            |> put_status(:not_found)
            |> json(%{error: "Satellite not found", id: id})
        end
    end
  end

  def update_mode(conn, %{"id" => _id}) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "Missing 'mode' parameter"})
  end

  @doc """
  PUT /api/satellites/:id/memory

  Updates a satellite's memory usage.

  Body: {"memory": 256.0}
  """
  def update_memory(conn, %{"id" => id, "memory" => memory})
      when is_number(memory) and memory >= 0 do
    case Satellite.update_memory(id, memory) do
      {:ok, state} ->
        # Broadcast the update
        StellarWeb.Endpoint.broadcast("satellites:lobby", "satellite_updated", serialize_state(state))

        json(conn, %{data: serialize_state(state)})

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Satellite not found", id: id})
    end
  end

  def update_memory(conn, %{"id" => _id}) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "Missing or invalid 'memory' parameter"})
  end

  # ============================================================================
  # Private Helpers
  # ============================================================================

  defp serialize_state(state) do
    %{
      id: state.id,
      mode: Atom.to_string(state.mode),
      energy: state.energy,
      memory_used: state.memory_used,
      position: %{
        x: elem(state.position, 0),
        y: elem(state.position, 1),
        z: elem(state.position, 2)
      }
    }
  end

  defp generate_id do
    "SAT-" <> (Ecto.UUID.generate() |> String.slice(0, 8) |> String.upcase())
  end

  defp parse_mode("nominal"), do: :nominal
  defp parse_mode("safe"), do: :safe
  defp parse_mode("survival"), do: :survival
  defp parse_mode(_), do: nil
end
