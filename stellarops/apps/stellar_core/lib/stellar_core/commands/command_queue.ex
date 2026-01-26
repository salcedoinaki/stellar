defmodule StellarCore.Commands.CommandQueue do
  @moduledoc """
  Command queue system for satellite operations.

  Manages queued, pending, and executed commands for satellites.
  Supports prioritization, scheduling, and retry logic.

  ## Command Lifecycle
  1. Created with :queued status
  2. Moved to :pending when sent to satellite
  3. :acknowledged when satellite confirms receipt
  4. :executing during execution
  5. :completed or :failed as terminal states
  6. :cancelled if aborted before execution

  ## Features
  - Priority-based queue ordering
  - Scheduled command execution
  - Automatic retry with exponential backoff
  - Command timeout handling
  - Real-time status broadcasting
  - **One command at a time per satellite**: A satellite must complete its
    current command before the next one is dispatched
  """

  use GenServer
  require Logger

  alias StellarData.Commands
  alias Phoenix.PubSub

  @pubsub StellarWeb.PubSub
  @default_timeout_ms 60_000
  @max_retries 3
  @tick_interval 5_000

  # ============================================================================
  # Client API
  # ============================================================================

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Queue a command for a satellite.

  ## Parameters
    - satellite_id: Target satellite ID
    - command_type: Type of command (e.g., :power, :attitude, :imaging)
    - payload: Command parameters
    - opts: Options including :priority, :scheduled_at, :timeout_ms

  ## Returns
    - {:ok, command} on success
    - {:error, reason} on failure
  """
  def queue_command(satellite_id, command_type, payload, opts \\ []) do
    GenServer.call(__MODULE__, {:queue_command, satellite_id, command_type, payload, opts})
  end

  @doc """
  Get all queued commands for a satellite.
  """
  def get_queue(satellite_id) do
    GenServer.call(__MODULE__, {:get_queue, satellite_id})
  end

  @doc """
  Get pending commands (sent but not yet acknowledged).
  """
  def get_pending(satellite_id) do
    GenServer.call(__MODULE__, {:get_pending, satellite_id})
  end

  @doc """
  Cancel a queued or pending command.
  """
  def cancel_command(command_id) do
    GenServer.call(__MODULE__, {:cancel_command, command_id})
  end

  @doc """
  Acknowledge command receipt from satellite.
  """
  def acknowledge_command(command_id) do
    GenServer.cast(__MODULE__, {:acknowledge, command_id})
  end

  @doc """
  Mark command execution started.
  """
  def start_execution(command_id) do
    GenServer.cast(__MODULE__, {:start_execution, command_id})
  end

  @doc """
  Complete a command successfully.
  """
  def complete_command(command_id, result \\ nil) do
    GenServer.cast(__MODULE__, {:complete, command_id, result})
  end

  @doc """
  Fail a command with error.
  """
  def fail_command(command_id, error) do
    GenServer.cast(__MODULE__, {:fail, command_id, error})
  end

  @doc """
  Process next commands in queue (called by scheduler).
  """
  def process_queue do
    GenServer.cast(__MODULE__, :process_queue)
  end

  # ============================================================================
  # Server Callbacks
  # ============================================================================

  @impl true
  def init(_opts) do
    Logger.info("CommandQueue starting")

    # Schedule periodic queue processing
    :timer.send_interval(@tick_interval, :tick)

    state = %{
      # In-memory cache of active commands by satellite
      # satellite_id => [%Command{}, ...]
      queues: %{},
      # Commands awaiting acknowledgment
      pending: %{},
      # Retry tracking
      retries: %{}
    }

    # Load any incomplete commands from database
    {:ok, load_active_commands(state)}
  end

  @impl true
  def handle_call({:queue_command, satellite_id, command_type, payload, opts}, _from, state) do
    priority = Keyword.get(opts, :priority, :normal)
    scheduled_at = Keyword.get(opts, :scheduled_at)
    timeout_ms = Keyword.get(opts, :timeout_ms, @default_timeout_ms)

    command_attrs = %{
      satellite_id: satellite_id,
      command_type: to_string(command_type),
      payload: payload,
      priority: priority_to_int(priority),
      status: :queued,
      scheduled_at: scheduled_at,
      timeout_ms: timeout_ms,
      created_at: DateTime.utc_now()
    }

    case Commands.create_command(command_attrs) do
      {:ok, command} ->
        new_state = add_to_queue(state, satellite_id, command)
        broadcast_command_update(command)
        Logger.debug("Queued command #{command.id} for satellite #{satellite_id}")
        {:reply, {:ok, command}, new_state}

      {:error, changeset} ->
        Logger.warning("Failed to create command: #{inspect(changeset.errors)}")
        {:reply, {:error, changeset}, state}
    end
  end

  @impl true
  def handle_call({:get_queue, satellite_id}, _from, state) do
    commands = Map.get(state.queues, satellite_id, [])
    queued = Enum.filter(commands, &(&1.status == :queued))
    {:reply, queued, state}
  end

  @impl true
  def handle_call({:get_pending, satellite_id}, _from, state) do
    pending =
      state.pending
      |> Map.values()
      |> Enum.filter(&(&1.satellite_id == satellite_id))

    {:reply, pending, state}
  end

  @impl true
  def handle_call({:cancel_command, command_id}, _from, state) do
    case find_command(state, command_id) do
      nil ->
        {:reply, {:error, :not_found}, state}

      command when command.status in [:queued, :pending] ->
        case Commands.update_command_status(command_id, :cancelled) do
          {:ok, updated} ->
            new_state = remove_command(state, command)
            broadcast_command_update(updated)
            {:reply, {:ok, updated}, new_state}

          {:error, reason} ->
            {:reply, {:error, reason}, state}
        end

      command ->
        {:reply, {:error, {:invalid_status, command.status}}, state}
    end
  end

  @impl true
  def handle_cast({:acknowledge, command_id}, state) do
    case Map.get(state.pending, command_id) do
      nil ->
        {:noreply, state}

      command ->
        Commands.update_command_status(command_id, :acknowledged)
        updated = %{command | status: :acknowledged}
        broadcast_command_update(updated)
        {:noreply, %{state | pending: Map.put(state.pending, command_id, updated)}}
    end
  end

  @impl true
  def handle_cast({:start_execution, command_id}, state) do
    case Map.get(state.pending, command_id) do
      nil ->
        {:noreply, state}

      command ->
        Commands.update_command_status(command_id, :executing)
        updated = %{command | status: :executing}
        broadcast_command_update(updated)
        {:noreply, %{state | pending: Map.put(state.pending, command_id, updated)}}
    end
  end

  @impl true
  def handle_cast({:complete, command_id, result}, state) do
    Logger.debug("CommandQueue completing command #{command_id}, pending keys: #{inspect(Map.keys(state.pending))}")
    case Map.get(state.pending, command_id) do
      nil ->
        Logger.warning("CommandQueue: command #{command_id} not found in pending map for completion")
        {:noreply, state}

      command ->
        Commands.update_command_status(command_id, :completed, result)
        updated = %{command | status: :completed}
        broadcast_command_update(updated)
        new_pending = Map.delete(state.pending, command_id)
        Logger.info("CommandQueue: command #{command_id} completed successfully")
        {:noreply, %{state | pending: new_pending, retries: Map.delete(state.retries, command_id)}}
    end
  end

  @impl true
  def handle_cast({:fail, command_id, error}, state) do
    case Map.get(state.pending, command_id) do
      nil ->
        {:noreply, state}

      command ->
        retry_count = Map.get(state.retries, command_id, 0)

        if retry_count < @max_retries do
          # Requeue with retry
          Logger.warning("Command #{command_id} failed (attempt #{retry_count + 1}), retrying")
          requeued = %{command | status: :queued}
          new_state =
            state
            |> Map.update!(:pending, &Map.delete(&1, command_id))
            |> add_to_queue(command.satellite_id, requeued)
            |> Map.update!(:retries, &Map.put(&1, command_id, retry_count + 1))

          broadcast_command_update(requeued)
          {:noreply, new_state}
        else
          # Max retries exceeded
          Logger.error("Command #{command_id} failed after #{@max_retries} retries: #{inspect(error)}")
          Commands.update_command_status(command_id, :failed, %{error: error})
          updated = %{command | status: :failed}
          broadcast_command_update(updated)

          new_pending = Map.delete(state.pending, command_id)
          {:noreply, %{state | pending: new_pending, retries: Map.delete(state.retries, command_id)}}
        end
    end
  end

  @impl true
  def handle_cast(:process_queue, state) do
    {:noreply, process_queues(state)}
  end

  @impl true
  def handle_info(:tick, state) do
    # Check for timeouts
    state = check_timeouts(state)
    # Process queues
    state = process_queues(state)
    {:noreply, state}
  end

  # ============================================================================
  # Private Functions
  # ============================================================================

  defp load_active_commands(state) do
    case Commands.list_active_commands() do
      commands when is_list(commands) ->
        Enum.reduce(commands, state, fn cmd, acc ->
          case cmd.status do
            :queued -> add_to_queue(acc, cmd.satellite_id, cmd)
            status when status in [:pending, :acknowledged, :executing] ->
              %{acc | pending: Map.put(acc.pending, cmd.id, cmd)}
            _ -> acc
          end
        end)

      _ ->
        state
    end
  end

  defp add_to_queue(state, satellite_id, command) do
    queue = Map.get(state.queues, satellite_id, [])
    # Insert sorted by priority (higher first) then inserted_at
    sorted = [command | queue] |> Enum.sort_by(&{-&1.priority, &1.inserted_at})
    %{state | queues: Map.put(state.queues, satellite_id, sorted)}
  end

  defp remove_command(state, command) do
    queue = Map.get(state.queues, command.satellite_id, [])
    filtered = Enum.reject(queue, &(&1.id == command.id))

    %{state |
      queues: Map.put(state.queues, command.satellite_id, filtered),
      pending: Map.delete(state.pending, command.id)
    }
  end

  defp find_command(state, command_id) do
    # Check pending first
    case Map.get(state.pending, command_id) do
      nil ->
        # Check all queues
        state.queues
        |> Map.values()
        |> List.flatten()
        |> Enum.find(&(&1.id == command_id))

      command ->
        command
    end
  end

  defp process_queues(state) do
    now = DateTime.utc_now()

    # Get satellites that already have a command in-flight (pending/executing)
    satellites_busy = 
      state.pending
      |> Map.values()
      |> Enum.map(& &1.satellite_id)
      |> MapSet.new()

    Enum.reduce(state.queues, state, fn {satellite_id, queue}, acc ->
      # Skip if this satellite already has a command being processed
      if MapSet.member?(satellites_busy, satellite_id) do
        acc
      else
        case get_next_ready_command(queue, now) do
          nil ->
            acc

          command ->
            # Send command to satellite
            send_command_to_satellite(satellite_id, command)

            # Move to pending
            updated_command = %{command | status: :pending, sent_at: now}
            Commands.update_command_status(command.id, :pending)
            broadcast_command_update(updated_command)

            # Update state
            remaining = Enum.reject(queue, &(&1.id == command.id))
            %{acc |
              queues: Map.put(acc.queues, satellite_id, remaining),
              pending: Map.put(acc.pending, command.id, updated_command)
            }
        end
      end
    end)
  end

  defp get_next_ready_command([], _now), do: nil
  defp get_next_ready_command([command | _rest], now) do
    cond do
      command.scheduled_at == nil ->
        command

      DateTime.compare(command.scheduled_at, now) in [:lt, :eq] ->
        command

      true ->
        nil
    end
  end

  defp send_command_to_satellite(satellite_id, command) do
    # Broadcast to satellite channel for transmission
    PubSub.broadcast(
      @pubsub,
      "satellite:#{satellite_id}:commands",
      {:command, command}
    )

    Logger.debug("Sent command #{command.id} to satellite #{satellite_id}")
  end

  defp check_timeouts(state) do
    now = DateTime.utc_now()

    timed_out =
      state.pending
      |> Enum.filter(fn {_id, cmd} ->
        case cmd.sent_at do
          nil -> false
          sent_at ->
            elapsed = DateTime.diff(now, sent_at, :millisecond)
            elapsed > (cmd.timeout_ms || @default_timeout_ms)
        end
      end)
      |> Enum.map(fn {id, _cmd} -> id end)

    # Fail timed out commands
    Enum.each(timed_out, fn command_id ->
      Logger.warning("Command #{command_id} timed out")
      fail_command(command_id, :timeout)
    end)

    state
  end

  defp priority_to_int(:critical), do: 100
  defp priority_to_int(:high), do: 75
  defp priority_to_int(:normal), do: 50
  defp priority_to_int(:low), do: 25
  defp priority_to_int(n) when is_integer(n), do: n

  defp broadcast_command_update(command) do
    PubSub.broadcast(
      @pubsub,
      "commands:updates",
      {:command_update, command}
    )

    PubSub.broadcast(
      @pubsub,
      "satellite:#{command.satellite_id}",
      {:command_update, command}
    )
  end
end
