defmodule StellarCore.Scheduler.MissionScheduler do
  @moduledoc """
  GenServer for mission scheduling with priority queue.

  The Mission Scheduler is responsible for:
  - Polling for pending missions
  - Priority-based scheduling (critical > high > normal > low)
  - Deadline-aware scheduling
  - Resource availability checking
  - Dispatching missions to satellites
  - Handling retries for failed missions

  ## Architecture

  The scheduler runs a periodic tick that:
  1. Fetches pending missions ordered by priority and deadline
  2. Checks satellite resource availability
  3. Schedules missions that can be executed
  4. Dispatches scheduled missions when it's time to run them
  """

  use GenServer
  require Logger

  alias StellarData.Missions
  alias StellarData.Missions.Mission
  alias StellarCore.Satellite

  @tick_interval :timer.seconds(5)
  @max_concurrent_per_satellite 3

  # ============================================================================
  # Client API
  # ============================================================================

  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Submits a new mission for scheduling.
  """
  def submit_mission(attrs, server \\ __MODULE__) do
    GenServer.call(server, {:submit_mission, attrs})
  end

  @doc """
  Gets the current scheduler status.
  """
  def status(server \\ __MODULE__) do
    GenServer.call(server, :status)
  end

  @doc """
  Forces an immediate scheduling tick.
  """
  def tick(server \\ __MODULE__) do
    GenServer.cast(server, :tick)
  end

  @doc """
  Pauses the scheduler.
  """
  def pause(server \\ __MODULE__) do
    GenServer.call(server, :pause)
  end

  @doc """
  Resumes the scheduler.
  """
  def resume(server \\ __MODULE__) do
    GenServer.call(server, :resume)
  end

  @doc """
  Reports mission completion.
  """
  def report_completion(mission_id, result, server \\ __MODULE__) do
    GenServer.cast(server, {:mission_completed, mission_id, result})
  end

  @doc """
  Reports mission failure.
  """
  def report_failure(mission_id, error, server \\ __MODULE__) do
    GenServer.cast(server, {:mission_failed, mission_id, error})
  end

  # ============================================================================
  # Server Callbacks
  # ============================================================================

  @impl true
  def init(opts) do
    Logger.info("Starting Mission Scheduler")

    state = %{
      running: true,
      tick_interval: Keyword.get(opts, :tick_interval, @tick_interval),
      max_concurrent: Keyword.get(opts, :max_concurrent, @max_concurrent_per_satellite),
      running_missions: %{},  # satellite_id => [mission_id, ...]
      stats: %{
        scheduled: 0,
        completed: 0,
        failed: 0,
        retried: 0
      }
    }

    # Schedule first tick
    schedule_tick(state)

    {:ok, state}
  end

  @impl true
  def handle_call({:submit_mission, attrs}, _from, state) do
    case Missions.create_mission(attrs) do
      {:ok, mission} ->
        Logger.info("Mission submitted: #{mission.id} (#{mission.name})")
        broadcast_event(:mission_submitted, mission)
        {:reply, {:ok, mission}, state}

      {:error, changeset} ->
        {:reply, {:error, changeset}, state}
    end
  end

  @impl true
  def handle_call(:status, _from, state) do
    status = %{
      running: state.running,
      running_missions: count_running_missions(state),
      stats: state.stats,
      pending: Missions.count_by_status()[:pending] || 0
    }

    {:reply, status, state}
  end

  @impl true
  def handle_call(:pause, _from, state) do
    Logger.info("Mission Scheduler paused")
    {:reply, :ok, %{state | running: false}}
  end

  @impl true
  def handle_call(:resume, _from, state) do
    Logger.info("Mission Scheduler resumed")
    schedule_tick(state)
    {:reply, :ok, %{state | running: true}}
  end

  @impl true
  def handle_cast(:tick, state) do
    new_state = if state.running, do: do_scheduling_tick(state), else: state
    schedule_tick(state)
    {:noreply, new_state}
  end

  @impl true
  def handle_cast({:mission_completed, mission_id, result}, state) do
    case Missions.get_mission(mission_id) do
      nil ->
        {:noreply, state}

      mission ->
        {:ok, updated} = Missions.complete_mission(mission, result)
        Logger.info("Mission completed: #{mission_id}")
        broadcast_event(:mission_completed, updated)

        new_state =
          state
          |> remove_running_mission(mission.satellite_id, mission_id)
          |> update_stat(:completed)

        {:noreply, new_state}
    end
  end

  @impl true
  def handle_cast({:mission_failed, mission_id, error}, state) do
    case Missions.get_mission(mission_id) do
      nil ->
        {:noreply, state}

      mission ->
        {:ok, updated} = Missions.fail_mission(mission, error)
        Logger.warning("Mission failed: #{mission_id} - #{error}")
        broadcast_event(:mission_failed, updated)

        # Raise alarm for mission failure
        raise_mission_alarm(updated, error)

        new_state =
          state
          |> remove_running_mission(mission.satellite_id, mission_id)
          |> update_stat(:failed)
          |> maybe_update_retry_stat(updated)

        {:noreply, new_state}
    end
  end

  @impl true
  def handle_info(:tick, state) do
    new_state = if state.running, do: do_scheduling_tick(state), else: state
    schedule_tick(state)
    {:noreply, new_state}
  end

  # ============================================================================
  # Scheduling Logic
  # ============================================================================

  defp do_scheduling_tick(state) do
    # 1. Get pending missions in priority order
    pending = Missions.get_pending_missions()

    # 2. Schedule and dispatch missions
    Enum.reduce(pending, state, fn mission, acc_state ->
      if can_schedule_mission?(mission, acc_state) do
        schedule_and_dispatch(mission, acc_state)
      else
        acc_state
      end
    end)
  end

  defp can_schedule_mission?(mission, state) do
    satellite_id = mission.satellite_id

    # Check concurrent mission limit
    running_count = get_running_count(state, satellite_id)

    if running_count >= state.max_concurrent do
      false
    else
      # Check satellite has resources
      case Satellite.get_state(satellite_id) do
        {:ok, sat_state} ->
          sat_state.energy >= mission.required_energy and
            (100 - sat_state.memory_used) >= mission.required_memory

        {:error, _} ->
          false
      end
    end
  end

  defp schedule_and_dispatch(mission, state) do
    now = DateTime.utc_now()

    # Schedule the mission
    case Missions.schedule_mission(mission, now) do
      {:ok, scheduled} ->
        # Start it immediately
        case Missions.start_mission(scheduled) do
          {:ok, running} ->
            # Dispatch to satellite
            dispatch_to_satellite(running)

            state
            |> add_running_mission(mission.satellite_id, mission.id)
            |> update_stat(:scheduled)

          {:error, reason} ->
            Logger.error("Failed to start mission #{mission.id}: #{reason}")
            state
        end

      {:error, reason} ->
        Logger.error("Failed to schedule mission #{mission.id}: #{reason}")
        state
    end
  end

  defp dispatch_to_satellite(mission) do
    Logger.info("Dispatching mission #{mission.id} to satellite #{mission.satellite_id}")

    # Execute the mission via the satellite server
    Task.Supervisor.start_child(StellarCore.TaskSupervisor, fn ->
      execute_mission(mission)
    end)
  end

  defp execute_mission(mission) do
    satellite_id = mission.satellite_id

    # Consume resources
    case Satellite.update_state(satellite_id, %{
           energy: -mission.required_energy,
           memory_used: mission.required_memory
         }) do
      {:ok, _} ->
        # Simulate mission execution
        Process.sleep(min(mission.estimated_duration * 100, 10_000))

        # Mission completed successfully
        report_completion(mission.id, %{
          executed_at: DateTime.utc_now(),
          duration_ms: mission.estimated_duration * 100
        })

        # Release memory
        Satellite.update_state(satellite_id, %{memory_used: -mission.required_memory})

      {:error, reason} ->
        report_failure(mission.id, "Resource allocation failed: #{inspect(reason)}")
    end
  rescue
    e ->
      report_failure(mission.id, "Execution error: #{Exception.message(e)}")
  end

  # ============================================================================
  # State Helpers
  # ============================================================================

  defp schedule_tick(%{running: true, tick_interval: interval}) do
    Process.send_after(self(), :tick, interval)
  end

  defp schedule_tick(_state), do: :ok

  defp add_running_mission(state, satellite_id, mission_id) do
    running = Map.get(state.running_missions, satellite_id, [])
    put_in(state.running_missions[satellite_id], [mission_id | running])
  end

  defp remove_running_mission(state, satellite_id, mission_id) do
    running = Map.get(state.running_missions, satellite_id, [])
    put_in(state.running_missions[satellite_id], List.delete(running, mission_id))
  end

  defp get_running_count(state, satellite_id) do
    state.running_missions
    |> Map.get(satellite_id, [])
    |> length()
  end

  defp count_running_missions(state) do
    state.running_missions
    |> Map.values()
    |> List.flatten()
    |> length()
  end

  defp update_stat(state, key) do
    update_in(state.stats[key], &(&1 + 1))
  end

  defp maybe_update_retry_stat(state, %Mission{status: :pending, retry_count: count})
       when count > 0 do
    update_stat(state, :retried)
  end

  defp maybe_update_retry_stat(state, _mission), do: state

  defp broadcast_event(event, mission) do
    Phoenix.PubSub.broadcast(
      StellarWeb.PubSub,
      "missions:events",
      {event, mission}
    )
  end

  defp raise_mission_alarm(mission, error) do
    alias StellarCore.Alarms

    if mission.status == :failed do
      # Permanently failed - critical alarm
      Alarms.mission_permanently_failed(mission.id, mission.name, error)
    else
      # Will retry - warning alarm
      Alarms.mission_failed(mission.id, mission.name, error, mission.retry_count)
    end
  end
end
