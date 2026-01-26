defmodule StellarCore.Commands.CommandExecutor do
  @moduledoc """
  Executes commands routed through ground stations to satellites.

  This GenServer subscribes to command broadcasts from the CommandQueue
  and processes them by:
  1. Finding an available online ground station
  2. Simulating command transmission delay
  3. Executing the command on the target satellite
  4. Reporting success/failure back to the CommandQueue

  ## Supported Command Types
  - `set_mode` - Change satellite operational mode
  - `collect_telemetry` - Force telemetry collection
  - `update_energy` - Adjust satellite energy level
  - `system_diagnostic` - Run system diagnostics
  - `reboot` - Restart satellite systems

  ## Architecture

  The executor subscribes to PubSub topics for each satellite:
  - `satellite:{satellite_id}:commands` - Incoming commands from queue

  Ground station selection is based on:
  - Station status (must be online)
  - Current load (prefer lower load)
  """

  use GenServer
  require Logger

  alias StellarCore.Satellite
  alias StellarCore.Commands.CommandQueue
  alias StellarData.GroundStations
  alias Phoenix.PubSub

  @pubsub StellarWeb.PubSub

  # Simulated transmission delay in ms (represents ground-to-satellite signal travel)
  @base_transmission_delay_ms 500
  @transmission_jitter_ms 500

  # Simulated execution delays by command type (in ms)
  # These simulate realistic onboard processing times
  @execution_delays %{
    "collect_telemetry" => {60_000, 5_000},    # 60-65 seconds for telemetry gathering
    "set_mode" => {1_000, 2_000},              # 1-3 seconds for mode change
    "system_diagnostic" => {30_000, 5_000},   # 30-35 seconds for diagnostics
    "update_energy" => {500, 1_000},           # 0.5-1.5 seconds
    "download_data" => {2_000, 4_000},         # 2-6 seconds base (plus size-based delay)
    "reboot" => {60_000, 5_000},               # 60-65 seconds for reboot
    "default" => {1_000, 2_000}                # 1-3 seconds for unknown commands
  }

  # ============================================================================
  # Client API
  # ============================================================================

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Get executor status and statistics.
  """
  def status do
    GenServer.call(__MODULE__, :status)
  end

  # ============================================================================
  # Server Callbacks
  # ============================================================================

  @impl true
  def init(_opts) do
    Logger.info("CommandExecutor starting")

    state = %{
      commands_executed: 0,
      commands_failed: 0,
      last_command_at: nil,
      subscribed_satellites: MapSet.new()
    }

    # Delay subscription to allow PubSub to start
    Process.send_after(self(), :subscribe, 1000)

    {:ok, state}
  end

  @impl true
  def handle_call(:status, _from, state) do
    {:reply, state, state}
  end

  @impl true
  def handle_info(:subscribe, state) do
    Logger.info("CommandExecutor subscribing to satellite command topics")

    # Subscribe to new satellite registrations to auto-subscribe
    PubSub.subscribe(@pubsub, "satellites:lifecycle")

    # Subscribe to existing satellites
    state = subscribe_to_existing_satellites(state)

    Logger.info("CommandExecutor subscribed to #{MapSet.size(state.subscribed_satellites)} satellites")
    {:noreply, state}
  end

  @impl true
  def handle_info({:command, command}, state) do
    Logger.info("CommandExecutor received command #{command.id} (#{command.command_type}) for #{command.satellite_id}")

    # Process command asynchronously to not block
    Task.start(fn -> execute_command(command) end)

    new_state = %{state | last_command_at: DateTime.utc_now()}
    {:noreply, new_state}
  end

  @impl true
  def handle_info({:satellite_started, satellite_id}, state) do
    # Subscribe to commands for this satellite
    {:noreply, subscribe_to_satellite(state, satellite_id)}
  end

  @impl true
  def handle_info({:satellite_stopped, satellite_id}, state) do
    # Unsubscribe from this satellite's commands
    topic = "satellite:#{satellite_id}:commands"
    PubSub.unsubscribe(@pubsub, topic)
    new_subscribed = MapSet.delete(state.subscribed_satellites, satellite_id)
    {:noreply, %{state | subscribed_satellites: new_subscribed}}
  end

  @impl true
  def handle_info(_msg, state) do
    {:noreply, state}
  end

  @impl true
  def handle_cast({:command_result, :success}, state) do
    {:noreply, %{state | commands_executed: state.commands_executed + 1}}
  end

  @impl true
  def handle_cast({:command_result, :failure}, state) do
    {:noreply, %{state | commands_failed: state.commands_failed + 1}}
  end

  # ============================================================================
  # Private Functions
  # ============================================================================

  defp subscribe_to_existing_satellites(state) do
    # Get all satellites from database and subscribe to their command topics
    satellites = StellarData.Satellites.list_satellites()

    Enum.reduce(satellites, state, fn sat, acc ->
      subscribe_to_satellite(acc, sat.id)
    end)
  end

  defp subscribe_to_satellite(state, satellite_id) do
    if MapSet.member?(state.subscribed_satellites, satellite_id) do
      state
    else
      topic = "satellite:#{satellite_id}:commands"
      PubSub.subscribe(@pubsub, topic)
      Logger.debug("Subscribed to #{topic}")
      %{state | subscribed_satellites: MapSet.put(state.subscribed_satellites, satellite_id)}
    end
  end

  defp execute_command(command) do
    # Step 1: Find an available ground station
    case find_available_ground_station() do
      nil ->
        Logger.warning("No ground station available for command #{command.id}")
        CommandQueue.fail_command(command.id, :no_ground_station)
        report_result(:failure)

      ground_station ->
        Logger.debug("Routing command #{command.id} through #{ground_station.code}")
        execute_via_ground_station(command, ground_station)
    end
  end

  defp find_available_ground_station do
    # Get online stations sorted by current load
    GroundStations.list_online_ground_stations()
    |> Enum.sort_by(& &1.current_load)
    |> List.first()
  end

  defp execute_via_ground_station(command, ground_station) do
    # Step 2: Acknowledge receipt
    CommandQueue.acknowledge_command(command.id)

    # Simulate transmission delay
    transmission_delay = @base_transmission_delay_ms + :rand.uniform(@transmission_jitter_ms)
    Process.sleep(transmission_delay)

    # Step 3: Start execution
    CommandQueue.start_execution(command.id)

    # Step 4: Execute the command on the satellite
    result = do_execute(command)

    # Log the ground station used
    Logger.info(
      "Command #{command.id} (#{command.command_type}) executed via #{ground_station.code}: #{inspect(result)}"
    )

    # Step 5: Report result
    case result do
      {:ok, data} ->
        # Extract the map from the tuple - result field expects a map, not a tuple
        CommandQueue.complete_command(command.id, data)
        report_result(:success)

      {:error, reason} ->
        CommandQueue.fail_command(command.id, reason)
        report_result(:failure)
    end
  end

  defp do_execute(command) do
    satellite_id = command.satellite_id
    command_type = command.command_type
    payload = command.payload || %{}

    # Simulate realistic execution delay before processing
    simulate_execution_delay(command_type)

    # Check if satellite is alive
    unless Satellite.alive?(satellite_id) do
      {:error, :satellite_not_running}
    else
      execute_command_type(satellite_id, command_type, payload)
    end
  end

  defp execute_command_type(satellite_id, "set_mode", payload) do
    mode = payload["mode"] || payload[:mode]

    if mode do
      mode_atom = if is_atom(mode), do: mode, else: String.to_existing_atom(mode)
      case Satellite.set_mode(satellite_id, mode_atom) do
        {:ok, state} ->
          {:ok, %{
            mode: state.mode,
            previous_mode: mode_atom,
            set_at: DateTime.utc_now()
          }}
        error ->
          error
      end
    else
      {:error, :missing_mode_parameter}
    end
  rescue
    ArgumentError -> {:error, :invalid_mode}
  end

  defp execute_command_type(satellite_id, "collect_telemetry", _payload) do
    # Simulate telemetry collection - just return current state
    case Satellite.get_state(satellite_id) do
      {:ok, state} ->
        # Convert position tuple to map for JSON encoding
        {x, y, z} = state.position || {0.0, 0.0, 0.0}
        {:ok, %{
          mode: state.mode,
          energy: state.energy,
          memory_used: state.memory_used,
          position: %{x: x, y: y, z: z},
          collected_at: DateTime.utc_now()
        }}

      error ->
        error
    end
  end

  defp execute_command_type(satellite_id, "update_energy", payload) do
    delta = payload["delta"] || payload[:delta] || 0
    case Satellite.update_energy(satellite_id, delta) do
      {:ok, state} ->
        {:ok, %{
          energy: state.energy,
          delta: delta,
          updated_at: DateTime.utc_now()
        }}
      error ->
        error
    end
  end

  defp execute_command_type(satellite_id, "system_diagnostic", _payload) do
    # Simulate diagnostic - return health info
    case Satellite.get_state(satellite_id) do
      {:ok, state} ->
        diagnostic = %{
          satellite_id: satellite_id,
          mode: state.mode,
          energy_ok: state.energy > 20,
          memory_ok: state.memory_used < 80,
          systems: %{
            power: :nominal,
            attitude: :nominal,
            thermal: :nominal,
            comms: :nominal
          },
          timestamp: DateTime.utc_now()
        }
        {:ok, diagnostic}

      error ->
        error
    end
  end

  defp execute_command_type(satellite_id, "download_data", payload) do
    # Simulate data download
    data_type = payload["type"] || payload[:type] || "general"
    size_mb = payload["size_mb"] || payload[:size_mb] || 100

    # Simulate download time based on size
    download_time_ms = div(size_mb, 10) * 100
    Process.sleep(min(download_time_ms, 1000))  # Cap at 1 second for demo

    {:ok, %{
      type: data_type,
      size_mb: size_mb,
      downloaded_at: DateTime.utc_now(),
      satellite_id: satellite_id
    }}
  end

  defp execute_command_type(satellite_id, "reboot", _payload) do
    # Simulate reboot - stop and restart the satellite
    Logger.info("Rebooting satellite #{satellite_id}")

    case Satellite.stop(satellite_id) do
      :ok ->
        Process.sleep(500)  # Simulate reboot time
        case Satellite.start(satellite_id) do
          {:ok, _pid} -> {:ok, %{rebooted_at: DateTime.utc_now()}}
          error -> error
        end

      error ->
        error
    end
  end

  defp execute_command_type(_satellite_id, command_type, _payload) do
    # Unknown command type - just succeed for demo purposes
    Logger.warning("Unknown command type: #{command_type}, simulating success")
    {:ok, %{command_type: command_type, status: :simulated, timestamp: DateTime.utc_now()}}
  end

  defp simulate_execution_delay(command_type) do
    {base_delay, jitter} = Map.get(@execution_delays, command_type, @execution_delays["default"])
    delay = base_delay + :rand.uniform(jitter)
    Logger.debug("Simulating #{command_type} execution delay: #{delay}ms")
    Process.sleep(delay)
  end

  defp report_result(result) do
    GenServer.cast(__MODULE__, {:command_result, result})
  end
end
