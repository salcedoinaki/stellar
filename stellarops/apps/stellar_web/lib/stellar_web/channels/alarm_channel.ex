defmodule StellarWeb.AlarmChannel do
  @moduledoc """
  WebSocket channel for real-time alarm notifications.

  Clients can join:
  - `alarms:all` - receive all alarm events
  - `alarms:satellite:<id>` - receive alarms for a specific satellite
  - `alarms:mission:<id>` - receive alarms for a specific mission

  Events pushed to clients:
  - alarm_raised: new alarm created
  - alarm_acknowledged: alarm acknowledged by user
  - alarm_resolved: alarm resolved
  """

  use Phoenix.Channel

  alias StellarCore.Alarms
  alias Phoenix.PubSub

  @pubsub StellarWeb.PubSub

  @impl true
  def join("alarms:all", _payload, socket) do
    PubSub.subscribe(@pubsub, "alarms:all")
    send(self(), :after_join)
    {:ok, socket}
  end

  def join("alarms:" <> source, _payload, socket) do
    # Subscribe to source-specific alarms
    PubSub.subscribe(@pubsub, "alarms:#{source}")
    {:ok, assign(socket, :source, source)}
  end

  @impl true
  def handle_info(:after_join, socket) do
    # Send current alarm summary on join
    summary = Alarms.get_summary()
    push(socket, "alarms_summary", summary)

    # Send active alarms
    active = Alarms.list_alarms(status: :active, limit: 50)
    push(socket, "active_alarms", %{alarms: Enum.map(active, &serialize_alarm/1)})

    {:noreply, socket}
  end

  # Handle PubSub broadcasts
  @impl true
  def handle_info({:alarm_raised, alarm}, socket) do
    push(socket, "alarm_raised", serialize_alarm(alarm))
    {:noreply, socket}
  end

  @impl true
  def handle_info({:alarm_acknowledged, alarm}, socket) do
    push(socket, "alarm_acknowledged", serialize_alarm(alarm))
    {:noreply, socket}
  end

  @impl true
  def handle_info({:alarm_resolved, alarm}, socket) do
    push(socket, "alarm_resolved", serialize_alarm(alarm))
    {:noreply, socket}
  end

  @impl true
  def handle_info(_msg, socket), do: {:noreply, socket}

  # Client commands

  @impl true
  def handle_in("get_summary", _payload, socket) do
    summary = Alarms.get_summary()
    {:reply, {:ok, summary}, socket}
  end

  @impl true
  def handle_in("get_active", _payload, socket) do
    alarms = Alarms.list_alarms(status: :active)
    {:reply, {:ok, %{alarms: Enum.map(alarms, &serialize_alarm/1)}}, socket}
  end

  @impl true
  def handle_in("get_alarm", %{"id" => id}, socket) do
    case Alarms.get_alarm(id) do
      {:ok, alarm} ->
        {:reply, {:ok, serialize_alarm(alarm)}, socket}

      {:error, :not_found} ->
        {:reply, {:error, %{reason: "not_found"}}, socket}
    end
  end

  @impl true
  def handle_in("acknowledge", %{"id" => id} = params, socket) do
    user = params["user"] || "websocket"

    case Alarms.acknowledge(id, user) do
      :ok ->
        {:ok, alarm} = Alarms.get_alarm(id)
        broadcast!(socket, "alarm_acknowledged", serialize_alarm(alarm))
        {:reply, {:ok, serialize_alarm(alarm)}, socket}

      {:error, :not_found} ->
        {:reply, {:error, %{reason: "not_found"}}, socket}
    end
  end

  @impl true
  def handle_in("resolve", %{"id" => id}, socket) do
    case Alarms.resolve(id) do
      :ok ->
        {:ok, alarm} = Alarms.get_alarm(id)
        broadcast!(socket, "alarm_resolved", serialize_alarm(alarm))
        {:reply, {:ok, serialize_alarm(alarm)}, socket}

      {:error, :not_found} ->
        {:reply, {:error, %{reason: "not_found"}}, socket}
    end
  end

  @impl true
  def handle_in(_event, _payload, socket) do
    {:reply, {:error, %{reason: "unknown_event"}}, socket}
  end

  # ============================================================================
  # Private Helpers
  # ============================================================================

  defp serialize_alarm(alarm) do
    %{
      id: alarm.id,
      type: alarm.type,
      severity: Atom.to_string(alarm.severity),
      message: alarm.message,
      source: alarm.source,
      details: alarm.details,
      status: Atom.to_string(alarm.status),
      created_at: DateTime.to_iso8601(alarm.created_at),
      acknowledged_at: format_datetime(alarm.acknowledged_at),
      acknowledged_by: alarm.acknowledged_by,
      resolved_at: format_datetime(alarm.resolved_at)
    }
  end

  defp format_datetime(nil), do: nil
  defp format_datetime(dt), do: DateTime.to_iso8601(dt)
end
