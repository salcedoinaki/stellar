defmodule StellarCore.Missions.Executor do
  @moduledoc """
  Mission execution engine.

  Executes missions on satellites by:
  1. Validating mission parameters
  2. Reserving satellite resources
  3. Sending commands to the satellite
  4. Monitoring execution progress
  5. Handling success/failure outcomes

  Supports different mission types:
  - imaging: Capture images of target coordinates
  - data_collection: Collect scientific data
  - orbit_adjust: Perform orbital maneuvers
  - downlink: Transfer data to ground station
  - maintenance: System maintenance tasks

  ## Mission Durations
  Missions simulate realistic satellite operations with configurable durations.
  In production, these would be hours to days; for demos, they're scaled to minutes.
  """

  use GenServer
  require Logger

  alias StellarCore.Satellite
  alias StellarCore.Alarms
  alias StellarCore.Missions.Validator
  alias StellarData.Missions
  alias StellarData.Missions.Mission
  alias Phoenix.PubSub

  @pubsub StellarWeb.PubSub
  @execution_timeout 600_000  # 10 minutes default (increased for longer missions)

  # Simulated mission execution durations by type (in ms)
  # Real missions take hours to days; these are scaled for demos
  @mission_durations %{
    "imaging" => {120_000, 60_000},          # 2-3 minutes (real: hours for orbit pass + capture)
    "data_collection" => {180_000, 60_000},  # 3-4 minutes (real: hours/days of data gathering)
    "orbit_adjust" => {90_000, 30_000},      # 1.5-2 minutes (real: hours for maneuver + verification)
    "downlink" => {60_000, 30_000},          # 1-1.5 minutes (real: depends on contact window)
    "maintenance" => {150_000, 60_000},      # 2.5-3.5 minutes (real: hours for full diagnostics)
    "maneuver" => {120_000, 60_000},         # 2-3 minutes (COA maneuver execution)
    "communication" => {60_000, 30_000},     # 1-1.5 minutes (relay operations)
    "default" => {60_000, 30_000}            # 1-1.5 minutes for unknown types
  }

  # Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Execute a mission.

  ## Parameters
    - mission: The Mission struct to execute
    - opts: Options
      - `:timeout` - Execution timeout in ms (default: 300_000)
      - `:async` - If true, returns immediately (default: false)

  ## Returns
    - {:ok, result} on success
    - {:error, reason} on failure
  """
  @spec execute(Mission.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def execute(%Mission{} = mission, opts \\ []) do
    if Keyword.get(opts, :async, false) do
      GenServer.cast(__MODULE__, {:execute, mission, opts})
      {:ok, :executing}
    else
      timeout = Keyword.get(opts, :timeout, @execution_timeout)
      GenServer.call(__MODULE__, {:execute, mission, opts}, timeout + 5_000)
    end
  end

  @doc """
  Cancel a running mission.
  """
  @spec cancel(binary(), String.t()) :: :ok | {:error, term()}
  def cancel(mission_id, reason \\ "Canceled by operator") do
    GenServer.call(__MODULE__, {:cancel, mission_id, reason})
  end

  @doc """
  Get status of running missions.
  """
  @spec status() :: map()
  def status do
    GenServer.call(__MODULE__, :status)
  end

  # Server Callbacks

  @impl true
  def init(_opts) do
    state = %{
      running_missions: %{},
      completed_count: 0,
      failed_count: 0
    }

    Logger.info("[MissionExecutor] Started")
    {:ok, state}
  end

  @impl true
  def handle_call({:execute, mission, opts}, from, state) do
    case do_execute(mission, opts, from, state) do
      {:executing, new_state} ->
        {:noreply, new_state}

      {:immediate, result, new_state} ->
        {:reply, result, new_state}
    end
  end

  @impl true
  def handle_call({:cancel, mission_id, reason}, _from, state) do
    case Map.get(state.running_missions, mission_id) do
      nil ->
        {:reply, {:error, :not_running}, state}

      running ->
        # Cancel the task
        if running.task_ref, do: Process.exit(running.task_pid, :cancelled)

        # Update mission in database
        Missions.cancel_mission(mission_id, reason)

        # Broadcast cancellation
        broadcast_mission_event(:mission_cancelled, mission_id, %{reason: reason})

        new_running = Map.delete(state.running_missions, mission_id)
        {:reply, :ok, %{state | running_missions: new_running}}
    end
  end

  @impl true
  def handle_call(:status, _from, state) do
    status = %{
      running_count: map_size(state.running_missions),
      running_missions: Map.keys(state.running_missions),
      completed_count: state.completed_count,
      failed_count: state.failed_count
    }

    {:reply, status, state}
  end

  @impl true
  def handle_cast({:execute, mission, opts}, state) do
    case do_execute(mission, opts, nil, state) do
      {:executing, new_state} ->
        {:noreply, new_state}

      {:immediate, _result, new_state} ->
        {:noreply, new_state}
    end
  end

  @impl true
  def handle_info({ref, result}, state) when is_reference(ref) do
    # Task completed
    case find_mission_by_ref(state.running_missions, ref) do
      {mission_id, running} ->
        Process.demonitor(ref, [:flush])
        handle_mission_complete(mission_id, running, result, state)

      nil ->
        {:noreply, state}
    end
  end

  @impl true
  def handle_info({:DOWN, ref, :process, _pid, reason}, state) do
    case find_mission_by_ref(state.running_missions, ref) do
      {mission_id, running} ->
        handle_mission_failed(mission_id, running, {:crash, reason}, state)

      nil ->
        {:noreply, state}
    end
  end

  # Private Functions

  defp do_execute(mission, opts, from, state) do
    # Validate mission
    case Validator.validate_for_execution(mission) do
      :ok ->
        start_mission_execution(mission, opts, from, state)

      {:error, errors} ->
        Logger.warning("[MissionExecutor] Validation failed for #{mission.id}",
          errors: errors
        )

        result = {:error, {:validation_failed, errors}}

        if from do
          {:immediate, result, state}
        else
          {:immediate, result, state}
        end
    end
  end

  defp start_mission_execution(mission, opts, from, state) do
    timeout = Keyword.get(opts, :timeout, @execution_timeout)

    # Mark mission as running in database
    {:ok, updated_mission} = Missions.start_mission(mission.id)

    # Broadcast start
    broadcast_mission_event(:mission_started, mission.id, %{
      satellite_id: mission.satellite_id,
      type: mission.type
    })

    Logger.info("[MissionExecutor] Starting mission #{mission.id}",
      satellite_id: mission.satellite_id,
      type: mission.type
    )

    # Start execution task
    task =
      Task.async(fn ->
        execute_mission_type(updated_mission, timeout)
      end)

    running = %{
      mission: updated_mission,
      task_ref: task.ref,
      task_pid: task.pid,
      from: from,
      started_at: DateTime.utc_now()
    }

    new_running = Map.put(state.running_missions, mission.id, running)
    {:executing, %{state | running_missions: new_running}}
  end

  defp execute_mission_type(mission, _timeout) do
    # Reserve resources on satellite
    with :ok <- reserve_resources(mission),
         {:ok, result} <- run_mission(mission),
         :ok <- release_resources(mission) do
      {:ok, result}
    else
      {:error, reason} ->
        # Attempt to release resources even on failure
        release_resources(mission)
        {:error, reason}
    end
  end

  defp reserve_resources(mission) do
    # Deduct energy and memory from satellite
    case Satellite.get_state(mission.satellite_id) do
      {:ok, state} ->
        new_energy = max(0, state.energy - mission.required_energy)
        new_memory = min(100, state.memory_used + mission.required_memory)

        with {:ok, :updated} <- Satellite.update_energy(mission.satellite_id, new_energy),
             {:ok, :updated} <- Satellite.update_memory(mission.satellite_id, new_memory) do
          :ok
        else
          _ -> {:error, :resource_reservation_failed}
        end

      {:error, _} ->
        {:error, :satellite_not_available}
    end
  end

  defp release_resources(mission) do
    # Release memory after mission completes
    case Satellite.get_state(mission.satellite_id) do
      {:ok, state} ->
        new_memory = max(0, state.memory_used - mission.required_memory)
        Satellite.update_memory(mission.satellite_id, new_memory)
        :ok

      {:error, _} ->
        :ok
    end
  end

  defp run_mission(mission) do
    case mission.type do
      "imaging" -> run_imaging_mission(mission)
      "data_collection" -> run_data_collection_mission(mission)
      "orbit_adjust" -> run_orbit_adjust_mission(mission)
      "downlink" -> run_downlink_mission(mission)
      "maintenance" -> run_maintenance_mission(mission)
      _ -> {:error, {:unknown_mission_type, mission.type}}
    end
  end

  defp run_imaging_mission(mission) do
    # Simulate imaging mission
    target_lat = get_in(mission.payload, ["target_lat"]) || 0.0
    target_lon = get_in(mission.payload, ["target_lon"]) || 0.0

    Logger.info("[MissionExecutor] Imaging target at #{target_lat}, #{target_lon}")

    # Simulate realistic mission duration
    simulate_mission_duration("imaging")

    {:ok, %{
      images_captured: :rand.uniform(10) + 1,
      target_lat: target_lat,
      target_lon: target_lon,
      resolution_m: 0.5,
      cloud_cover_percent: :rand.uniform(30)
    }}
  end

  defp run_data_collection_mission(mission) do
    Logger.info("[MissionExecutor] Collecting data for #{mission.satellite_id}")

    # Simulate realistic mission duration
    simulate_mission_duration("data_collection")

    {:ok, %{
      samples_collected: :rand.uniform(1000) + 100,
      data_size_mb: :rand.uniform(500) + 50,
      sensors_used: ["magnetometer", "spectrometer", "temperature"]
    }}
  end

  defp run_orbit_adjust_mission(mission) do
    delta_v = get_in(mission.payload, ["delta_v_m_s"]) || 1.0

    Logger.info("[MissionExecutor] Orbit adjustment: delta-v #{delta_v} m/s")

    # Simulate realistic mission duration
    simulate_mission_duration("orbit_adjust")

    {:ok, %{
      delta_v_applied: delta_v,
      fuel_used_kg: delta_v * 0.1,
      new_orbit_verified: true
    }}
  end

  defp run_downlink_mission(mission) do
    data_size = get_in(mission.payload, ["data_size_mb"]) || 100

    Logger.info("[MissionExecutor] Downlinking #{data_size} MB")

    # Simulate realistic mission duration
    simulate_mission_duration("downlink")

    {:ok, %{
      data_transferred_mb: data_size,
      transfer_rate_mbps: mission.required_bandwidth,
      checksum_verified: true
    }}
  end

  defp run_maintenance_mission(mission) do
    maintenance_type = get_in(mission.payload, ["maintenance_type"]) || "general"

    Logger.info("[MissionExecutor] Running #{maintenance_type} maintenance")

    # Simulate realistic mission duration
    simulate_mission_duration("maintenance")

    {:ok, %{
      maintenance_type: maintenance_type,
      health_checks_passed: true,
      diagnostics: %{
        memory_cleared_mb: :rand.uniform(50),
        logs_rotated: true,
        firmware_version: "v2.3.1"
      }
    }}
  end

  defp handle_mission_complete(mission_id, running, result, state) do
    case result do
      {:ok, mission_result} ->
        # Update mission in database
        Missions.complete_mission(mission_id, mission_result)

        broadcast_mission_event(:mission_completed, mission_id, mission_result)

        Logger.info("[MissionExecutor] Mission #{mission_id} completed successfully")

        # Reply to caller if synchronous
        if running.from, do: GenServer.reply(running.from, {:ok, mission_result})

        new_running = Map.delete(state.running_missions, mission_id)
        new_state = %{state | 
          running_missions: new_running,
          completed_count: state.completed_count + 1
        }

        {:noreply, new_state}

      {:error, reason} ->
        handle_mission_failed(mission_id, running, reason, state)
    end
  end

  defp handle_mission_failed(mission_id, running, reason, state) do
    error_str = inspect(reason)

    # Update mission in database (with retry logic)
    Missions.fail_mission(mission_id, error_str)

    # Raise alarm for significant failures
    if running.mission.retry_count >= running.mission.max_retries - 1 do
      Alarms.mission_permanently_failed(
        mission_id,
        running.mission.name,
        error_str
      )
    else
      Alarms.mission_failed(
        mission_id,
        running.mission.name,
        error_str,
        running.mission.retry_count + 1
      )
    end

    broadcast_mission_event(:mission_failed, mission_id, %{error: error_str})

    Logger.warning("[MissionExecutor] Mission #{mission_id} failed: #{error_str}")

    # Reply to caller if synchronous
    if running.from, do: GenServer.reply(running.from, {:error, reason})

    new_running = Map.delete(state.running_missions, mission_id)
    new_state = %{state | 
      running_missions: new_running,
      failed_count: state.failed_count + 1
    }

    {:noreply, new_state}
  end

  defp find_mission_by_ref(running_missions, ref) do
    Enum.find_value(running_missions, fn {mission_id, running} ->
      if running.task_ref == ref do
        {mission_id, running}
      end
    end)
  end

  defp broadcast_mission_event(event, mission_id, payload) do
    PubSub.broadcast(@pubsub, "missions:all", {event, mission_id, payload})
    PubSub.broadcast(@pubsub, "mission:#{mission_id}", {event, payload})
  end

  defp simulate_mission_duration(mission_type) do
    {base_delay, jitter} = Map.get(@mission_durations, mission_type, @mission_durations["default"])
    delay = base_delay + :rand.uniform(jitter)
    Logger.info("[MissionExecutor] Mission duration: #{div(delay, 1000)} seconds")
    Process.sleep(delay)
  end
end
