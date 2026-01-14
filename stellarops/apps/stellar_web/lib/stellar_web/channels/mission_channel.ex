defmodule StellarWeb.MissionChannel do
  @moduledoc """
  WebSocket channel for real-time mission updates.

  Clients can join `missions:lobby` to receive broadcasts about:
  - mission_submitted: new mission submitted to scheduler
  - mission_scheduled: mission scheduled for execution
  - mission_started: mission execution started
  - mission_completed: mission completed successfully
  - mission_failed: mission failed (may retry)

  Clients can also send commands:
  - get_pending: request all pending missions
  - get_status: request scheduler status
  """

  use Phoenix.Channel

  alias StellarCore.Scheduler.MissionScheduler
  alias StellarData.Missions
  alias Phoenix.PubSub

  @pubsub StellarWeb.PubSub

  @impl true
  def join("missions:lobby", _payload, socket) do
    # Subscribe to mission events
    PubSub.subscribe(@pubsub, "missions:events")
    send(self(), :after_join)
    {:ok, socket}
  end

  def join("missions:" <> satellite_id, _payload, socket) do
    # Subscribe to satellite-specific mission events
    PubSub.subscribe(@pubsub, "missions:satellite:#{satellite_id}")
    {:ok, assign(socket, :satellite_id, satellite_id)}
  end

  @impl true
  def handle_info(:after_join, socket) do
    status = MissionScheduler.status()
    push(socket, "scheduler_status", status)
    {:noreply, socket}
  end

  # Handle PubSub broadcasts for mission events
  @impl true
  def handle_info({:mission_submitted, mission}, socket) do
    push(socket, "mission_submitted", serialize_mission(mission))
    {:noreply, socket}
  end

  @impl true
  def handle_info({:mission_scheduled, mission}, socket) do
    push(socket, "mission_scheduled", serialize_mission(mission))
    {:noreply, socket}
  end

  @impl true
  def handle_info({:mission_started, mission}, socket) do
    push(socket, "mission_started", serialize_mission(mission))
    {:noreply, socket}
  end

  @impl true
  def handle_info({:mission_completed, mission}, socket) do
    push(socket, "mission_completed", serialize_mission(mission))
    {:noreply, socket}
  end

  @impl true
  def handle_info({:mission_failed, mission}, socket) do
    push(socket, "mission_failed", serialize_mission(mission))
    {:noreply, socket}
  end

  @impl true
  def handle_info(_msg, socket), do: {:noreply, socket}

  @impl true
  def handle_in("get_pending", _payload, socket) do
    missions = Missions.get_pending_missions()
    {:reply, {:ok, %{missions: Enum.map(missions, &serialize_mission/1)}}, socket}
  end

  @impl true
  def handle_in("get_status", _payload, socket) do
    status = MissionScheduler.status()
    {:reply, {:ok, status}, socket}
  end

  @impl true
  def handle_in("submit_mission", payload, socket) do
    attrs = %{
      name: payload["name"],
      type: payload["type"],
      satellite_id: payload["satellite_id"],
      priority: parse_priority(payload["priority"]),
      required_energy: payload["required_energy"] || 10.0,
      required_memory: payload["required_memory"] || 5.0
    }

    case MissionScheduler.submit_mission(attrs) do
      {:ok, mission} ->
        broadcast!(socket, "mission_submitted", serialize_mission(mission))
        {:reply, {:ok, serialize_mission(mission)}, socket}

      {:error, changeset} ->
        errors = format_changeset_errors(changeset)
        {:reply, {:error, %{errors: errors}}, socket}
    end
  end

  @impl true
  def handle_in("pause_scheduler", _payload, socket) do
    :ok = MissionScheduler.pause()
    broadcast!(socket, "scheduler_paused", %{})
    {:reply, :ok, socket}
  end

  @impl true
  def handle_in("resume_scheduler", _payload, socket) do
    :ok = MissionScheduler.resume()
    broadcast!(socket, "scheduler_resumed", %{})
    {:reply, :ok, socket}
  end

  @impl true
  def handle_in(_event, _payload, socket) do
    {:reply, {:error, %{reason: "unknown_event"}}, socket}
  end

  # ============================================================================
  # Private Helpers
  # ============================================================================

  defp serialize_mission(mission) do
    %{
      id: mission.id,
      name: mission.name,
      type: mission.type,
      satellite_id: mission.satellite_id,
      priority: Atom.to_string(mission.priority),
      status: Atom.to_string(mission.status),
      retry_count: mission.retry_count,
      max_retries: mission.max_retries,
      required_energy: mission.required_energy,
      required_memory: mission.required_memory,
      scheduled_at: format_datetime(mission.scheduled_at),
      started_at: format_datetime(mission.started_at),
      completed_at: format_datetime(mission.completed_at),
      last_error: mission.last_error
    }
  end

  defp format_datetime(nil), do: nil
  defp format_datetime(dt), do: DateTime.to_iso8601(dt)

  defp parse_priority("critical"), do: :critical
  defp parse_priority("high"), do: :high
  defp parse_priority("normal"), do: :normal
  defp parse_priority("low"), do: :low
  defp parse_priority(_), do: :normal

  defp format_changeset_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
  end
end
