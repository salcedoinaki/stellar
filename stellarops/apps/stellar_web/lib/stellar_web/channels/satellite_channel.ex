defmodule StellarWeb.SatelliteChannel do
  @moduledoc """
  WebSocket channel for real-time satellite updates.

  Clients can join `satellites:lobby` to receive broadcasts about:
  - satellite_created: when a new satellite is spawned
  - satellite_updated: when a satellite's state changes
  - satellite_deleted: when a satellite is stopped

  Clients can also send commands:
  - get_all: request current state of all satellites
  - get_satellite: request state of a specific satellite

  ## Heartbeat (TASK-128)
  
  The channel supports application-level heartbeat messages in addition
  to Phoenix's built-in transport-level heartbeat. Clients can send
  "heartbeat" messages and receive a "heartbeat_ack" response with
  server timestamp for latency measurement.
  """

  use Phoenix.Channel

  alias StellarCore.Satellite

  # Heartbeat interval for server-initiated heartbeats (30 seconds)
  @heartbeat_interval_ms 30_000

  @impl true
  def join("satellites:lobby", _payload, socket) do
    # Send current satellite states on join
    send(self(), :after_join)
    # Schedule server-initiated heartbeat
    schedule_heartbeat()
    socket = assign(socket, :last_heartbeat, System.system_time(:millisecond))
    {:ok, socket}
  end

  def join("satellites:" <> _id, _payload, socket) do
    # Could be used for per-satellite channels in the future
    socket = assign(socket, :last_heartbeat, System.system_time(:millisecond))
    {:ok, socket}
  end

  @impl true
  def handle_info(:after_join, socket) do
    satellites =
      Satellite.list_states()
      |> Enum.map(&serialize_state/1)

    push(socket, "satellites_list", %{satellites: satellites})
    {:noreply, socket}
  end

  @impl true
  def handle_info(:send_heartbeat, socket) do
    now = System.system_time(:millisecond)
    push(socket, "server_heartbeat", %{timestamp: now})
    schedule_heartbeat()
    {:noreply, socket}
  end

  @impl true
  def handle_in("get_all", _payload, socket) do
    satellites =
      Satellite.list_states()
      |> Enum.map(&serialize_state/1)

    {:reply, {:ok, %{satellites: satellites}}, socket}
  end

  # Heartbeat handling (TASK-128)
  # Client can send heartbeat messages for latency measurement
  @impl true
  def handle_in("heartbeat", payload, socket) do
    now = System.system_time(:millisecond)
    client_timestamp = Map.get(payload, "timestamp", 0)
    socket = assign(socket, :last_heartbeat, now)

    {:reply, {:ok, %{
      server_timestamp: now,
      client_timestamp: client_timestamp,
      latency: if(client_timestamp > 0, do: now - client_timestamp, else: nil)
    }}, socket}
  end

  # Respond to heartbeat_ack from client (confirms client received server heartbeat)
  @impl true
  def handle_in("heartbeat_ack", _payload, socket) do
    now = System.system_time(:millisecond)
    socket = assign(socket, :last_heartbeat, now)
    {:noreply, socket}
  end

  @impl true
  def handle_in("get_satellite", %{"id" => id}, socket) do
    case Satellite.fetch_state(id) do
      {:ok, state} ->
        {:reply, {:ok, serialize_state(state)}, socket}

      {:error, :not_found} ->
        {:reply, {:error, %{reason: "not_found"}}, socket}
    end
  end

  @impl true
  def handle_in("create_satellite", payload, socket) do
    id = Map.get(payload, "id", generate_id())

    case Satellite.start(id) do
      {:ok, _pid} ->
        {:ok, state} = Satellite.get_state(id)
        broadcast!(socket, "satellite_created", serialize_state(state))
        {:reply, {:ok, serialize_state(state)}, socket}

      {:error, :already_exists} ->
        {:reply, {:error, %{reason: "already_exists"}}, socket}

      {:error, reason} ->
        {:reply, {:error, %{reason: inspect(reason)}}, socket}
    end
  end

  @impl true
  def handle_in("update_energy", %{"id" => id, "delta" => delta}, socket)
      when is_number(delta) do
    case Satellite.update_energy(id, delta) do
      {:ok, state} ->
        broadcast!(socket, "satellite_updated", serialize_state(state))
        {:reply, {:ok, serialize_state(state)}, socket}

      {:error, :not_found} ->
        {:reply, {:error, %{reason: "not_found"}}, socket}
    end
  end

  @impl true
  def handle_in("set_mode", %{"id" => id, "mode" => mode_str}, socket) do
    mode = parse_mode(mode_str)

    cond do
      mode == nil ->
        {:reply, {:error, %{reason: "invalid_mode"}}, socket}

      true ->
        case Satellite.set_mode(id, mode) do
          {:ok, state} ->
            broadcast!(socket, "satellite_updated", serialize_state(state))
            {:reply, {:ok, serialize_state(state)}, socket}

          {:error, :not_found} ->
            {:reply, {:error, %{reason: "not_found"}}, socket}
        end
    end
  end

  @impl true
  def handle_in("delete_satellite", %{"id" => id}, socket) do
    case Satellite.stop(id) do
      :ok ->
        broadcast!(socket, "satellite_deleted", %{id: id})
        {:reply, {:ok, %{id: id}}, socket}

      {:error, :not_found} ->
        {:reply, {:error, %{reason: "not_found"}}, socket}
    end
  end

  # Catch-all for unknown messages
  @impl true
  def handle_in(_event, _payload, socket) do
    {:reply, {:error, %{reason: "unknown_event"}}, socket}
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

  defp schedule_heartbeat do
    Process.send_after(self(), :send_heartbeat, @heartbeat_interval_ms)
  end
end
