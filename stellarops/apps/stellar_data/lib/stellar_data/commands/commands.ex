defmodule StellarData.Commands do
  @moduledoc """
  Context module for command persistence and management.
  """

  import Ecto.Query, warn: false
  alias StellarData.Repo
  alias StellarData.Commands.Command

  @doc """
  Creates a new command.

  Accepts a map with command attributes.
  """
  def create_command(attrs) when is_map(attrs) do
    %Command{}
    |> Command.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Creates a new command for a satellite (legacy signature).
  """
  def create_command(satellite_id, command_type, params \\ %{}, opts \\ []) do
    attrs = %{
      satellite_id: satellite_id,
      command_type: command_type,
      params: params,
      priority: Keyword.get(opts, :priority, 50),
      scheduled_at: Keyword.get(opts, :scheduled_at)
    }

    create_command(attrs)
  end

  @doc """
  Gets a command by ID.
  """
  def get_command(id) do
    Repo.get(Command, id)
  end

  @doc """
  Gets a command by ID.

  Raises if not found.
  """
  def get_command!(id) do
    Repo.get!(Command, id)
  end

  @doc """
  Lists all active (non-terminal) commands.
  """
  def list_active_commands do
    Command
    |> where([c], c.status in [:queued, :pending, :acknowledged, :executing])
    |> order_by([c], [desc: c.priority, asc: c.inserted_at])
    |> Repo.all()
  end

  @doc """
  Gets queued commands for a satellite, ordered by priority and creation time.
  """
  def get_queued_commands(satellite_id) do
    Command
    |> where([c], c.satellite_id == ^satellite_id)
    |> where([c], c.status == :queued)
    |> order_by([c], [desc: c.priority, asc: c.inserted_at])
    |> Repo.all()
  end

  @doc """
  Gets pending commands for a satellite.
  """
  def get_pending_commands(satellite_id) do
    Command
    |> where([c], c.satellite_id == ^satellite_id)
    |> where([c], c.status in [:pending, :acknowledged, :executing])
    |> order_by([c], [desc: c.priority, asc: c.inserted_at])
    |> Repo.all()
  end

  @doc """
  Gets the next command to execute for a satellite.
  """
  def get_next_command(satellite_id) do
    now = DateTime.utc_now()

    Command
    |> where([c], c.satellite_id == ^satellite_id)
    |> where([c], c.status == :queued)
    |> where([c], is_nil(c.scheduled_at) or c.scheduled_at <= ^now)
    |> order_by([c], [desc: c.priority, asc: c.inserted_at])
    |> limit(1)
    |> Repo.one()
  end

  @doc """
  Updates a command's status by ID.
  """
  def update_command_status(command_id, status, result \\ nil) when is_atom(status) do
    case get_command(command_id) do
      nil ->
        {:error, :not_found}

      command ->
        attrs = %{status: status}

        attrs =
          case status do
            :pending -> Map.put(attrs, :sent_at, DateTime.utc_now())
            :executing -> Map.put(attrs, :started_at, DateTime.utc_now())
            s when s in [:completed, :failed, :cancelled] ->
              attrs = Map.put(attrs, :completed_at, DateTime.utc_now())
              if result, do: Map.put(attrs, :result, result), else: attrs
            _ -> attrs
          end

        command
        |> Command.status_changeset(attrs)
        |> Repo.update()
    end
  end

  @doc """
  Marks a command as running (executing).
  """
  def start_command(%Command{} = command) do
    command
    |> Command.status_changeset(%{
      status: :executing,
      started_at: DateTime.utc_now()
    })
    |> Repo.update()
  end

  @doc """
  Marks a command as completed successfully.
  """
  def complete_command(%Command{} = command, result \\ %{}) do
    command
    |> Command.status_changeset(%{
      status: :completed,
      completed_at: DateTime.utc_now(),
      result: result
    })
    |> Repo.update()
  end

  @doc """
  Marks a command as failed.
  """
  def fail_command(%Command{} = command, error_message) do
    command
    |> Command.status_changeset(%{
      status: :failed,
      completed_at: DateTime.utc_now(),
      error_message: error_message
    })
    |> Repo.update()
  end

  @doc """
  Cancels a queued or pending command.
  """
  def cancel_command(%Command{} = command) do
    command
    |> Command.status_changeset(%{
      status: :cancelled,
      completed_at: DateTime.utc_now()
    })
    |> Repo.update()
  end

  @doc """
  Gets command history for a satellite.
  """
  def get_command_history(satellite_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 100)
    status = Keyword.get(opts, :status)

    Command
    |> where([c], c.satellite_id == ^satellite_id)
    |> maybe_filter_status(status)
    |> order_by([c], desc: c.inserted_at)
    |> limit(^limit)
    |> Repo.all()
  end

  @doc """
  Gets command counts by status for a satellite.
  """
  def get_command_counts(satellite_id) do
    Command
    |> where([c], c.satellite_id == ^satellite_id)
    |> group_by([c], c.status)
    |> select([c], {c.status, count(c.id)})
    |> Repo.all()
    |> Map.new()
  end

  # Private helpers

  defp maybe_filter_status(query, nil), do: query
  defp maybe_filter_status(query, status) do
    where(query, [c], c.status == ^status)
  end
end
