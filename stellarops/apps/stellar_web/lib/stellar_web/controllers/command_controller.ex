defmodule StellarWeb.CommandController do
  @moduledoc """
  REST API controller for satellite command management.

  Provides endpoints for:
  - Creating/queuing commands
  - Viewing command status
  - Cancelling commands
  - Getting command history
  """

  use StellarWeb, :controller

  alias StellarCore.Commands.CommandQueue
  alias StellarData.Commands

  action_fallback StellarWeb.FallbackController

  @doc """
  List commands for a satellite.

  Query params:
  - status: Filter by status (queued, pending, completed, failed)
  - limit: Maximum number to return (default: 50)
  """
  def index(conn, %{"satellite_id" => satellite_id} = params) do
    limit = Map.get(params, "limit", "50") |> String.to_integer()
    status = Map.get(params, "status")

    opts = [limit: limit]
    opts = if status, do: [{:status, String.to_atom(status)} | opts], else: opts

    commands = Commands.get_command_history(satellite_id, opts)

    conn
    |> put_status(:ok)
    |> json(%{
      data: Enum.map(commands, &serialize_command/1),
      meta: %{count: length(commands)}
    })
  end

  @doc """
  Get a specific command by ID.
  """
  def show(conn, %{"id" => id}) do
    case Commands.get_command(id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Command not found"})

      command ->
        conn
        |> put_status(:ok)
        |> json(%{data: serialize_command(command)})
    end
  end

  @doc """
  Create and queue a new command.

  Body:
  - satellite_id: Target satellite
  - command_type: Type of command (required)
  - payload: Command parameters (optional)
  - priority: Priority level (optional, default: normal)
  - scheduled_at: ISO8601 timestamp for scheduled execution (optional)
  """
  def create(conn, params) do
    with {:ok, satellite_id} <- get_required(params, "satellite_id"),
         {:ok, command_type} <- get_required(params, "command_type") do
      payload = Map.get(params, "payload", %{})
      priority = Map.get(params, "priority", "normal") |> parse_priority()
      scheduled_at = parse_scheduled_at(Map.get(params, "scheduled_at"))

      opts = [priority: priority]
      opts = if scheduled_at, do: [{:scheduled_at, scheduled_at} | opts], else: opts

      case CommandQueue.queue_command(satellite_id, command_type, payload, opts) do
        {:ok, command} ->
          conn
          |> put_status(:created)
          |> json(%{
            data: serialize_command(command),
            message: "Command queued successfully"
          })

        {:error, changeset} ->
          conn
          |> put_status(:unprocessable_entity)
          |> json(%{error: "Failed to create command", details: format_errors(changeset)})
      end
    else
      {:error, field} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "Missing required field: #{field}"})
    end
  end

  @doc """
  Cancel a queued or pending command.
  """
  def cancel(conn, %{"id" => id}) do
    case CommandQueue.cancel_command(id) do
      {:ok, command} ->
        conn
        |> put_status(:ok)
        |> json(%{
          data: serialize_command(command),
          message: "Command cancelled"
        })

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Command not found"})

      {:error, {:invalid_status, status}} ->
        conn
        |> put_status(:conflict)
        |> json(%{error: "Cannot cancel command in #{status} status"})

      {:error, reason} ->
        conn
        |> put_status(:internal_server_error)
        |> json(%{error: "Failed to cancel command", reason: inspect(reason)})
    end
  end

  @doc """
  Get queue for a satellite.
  """
  def queue(conn, %{"satellite_id" => satellite_id}) do
    queued = CommandQueue.get_queue(satellite_id)
    pending = CommandQueue.get_pending(satellite_id)

    conn
    |> put_status(:ok)
    |> json(%{
      data: %{
        queued: Enum.map(queued, &serialize_command/1),
        pending: Enum.map(pending, &serialize_command/1)
      },
      meta: %{
        queued_count: length(queued),
        pending_count: length(pending)
      }
    })
  end

  @doc """
  Get command counts by status for a satellite.
  """
  def counts(conn, %{"satellite_id" => satellite_id}) do
    counts = Commands.get_command_counts(satellite_id)

    conn
    |> put_status(:ok)
    |> json(%{data: counts})
  end

  # Private helpers

  defp get_required(params, field) do
    case Map.get(params, field) do
      nil -> {:error, field}
      value -> {:ok, value}
    end
  end

  defp parse_priority("critical"), do: :critical
  defp parse_priority("high"), do: :high
  defp parse_priority("normal"), do: :normal
  defp parse_priority("low"), do: :low
  defp parse_priority(_), do: :normal

  defp parse_scheduled_at(nil), do: nil
  defp parse_scheduled_at(timestamp) when is_binary(timestamp) do
    case DateTime.from_iso8601(timestamp) do
      {:ok, dt, _offset} -> dt
      _ -> nil
    end
  end
  defp parse_scheduled_at(_), do: nil

  defp serialize_command(command) do
    %{
      id: command.id,
      satellite_id: command.satellite_id,
      command_type: command.command_type,
      payload: command.payload || command.params || %{},
      status: command.status,
      priority: command.priority,
      scheduled_at: format_datetime(command.scheduled_at),
      sent_at: format_datetime(Map.get(command, :sent_at)),
      started_at: format_datetime(command.started_at),
      completed_at: format_datetime(command.completed_at),
      result: command.result,
      error_message: command.error_message,
      created_at: format_datetime(command.inserted_at),
      updated_at: format_datetime(command.updated_at)
    }
  end

  defp format_datetime(nil), do: nil
  defp format_datetime(%DateTime{} = dt), do: DateTime.to_iso8601(dt)
  defp format_datetime(_), do: nil

  defp format_errors(%Ecto.Changeset{} = changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
  end
  defp format_errors(error), do: inspect(error)
end
