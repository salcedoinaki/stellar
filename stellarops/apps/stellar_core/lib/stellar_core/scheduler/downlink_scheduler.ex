defmodule StellarCore.Scheduler.DownlinkScheduler do
  @moduledoc """
  Downlink scheduling service.

  Manages the scheduling and execution of data downlink sessions
  during satellite-ground station contact windows.

  ## Features
  - Automatic scheduling based on contact windows
  - Priority-based queue management
  - Bandwidth allocation
  - Progress tracking
  - Automatic retry on failure

  ## Downlink Priorities
  1. Critical telemetry (anomaly data, emergency status)
  2. Command acknowledgments
  3. High-priority mission data
  4. Standard telemetry
  5. Stored science data
  6. Housekeeping data
  """

  use GenServer
  require Logger

  alias StellarData.GroundStations
  alias StellarCore.Commands.CommandQueue
  alias Phoenix.PubSub

  @pubsub StellarWeb.PubSub
  @schedule_interval 30_000  # Re-check schedule every 30 seconds
  @lookahead_minutes 30      # Schedule downlinks 30 minutes ahead

  defstruct [
    # Scheduled downlink sessions
    scheduled: [],
    # Currently active sessions
    active: %{},
    # Completed session stats
    stats: %{total: 0, completed: 0, failed: 0, data_transferred_mb: 0}
  ]

  # ============================================================================
  # Client API
  # ============================================================================

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Queue data for downlink.

  ## Parameters
    - satellite_id: Source satellite
    - data_type: Type of data (telemetry, science, command_ack, etc.)
    - size_bytes: Size of data to downlink
    - priority: Priority level (1-10, higher = more urgent)
    - opts: Additional options

  ## Returns
    - {:ok, downlink_id}
    - {:error, reason}
  """
  def queue_downlink(satellite_id, data_type, size_bytes, priority \\ 5, opts \\ []) do
    GenServer.call(__MODULE__, {:queue_downlink, satellite_id, data_type, size_bytes, priority, opts})
  end

  @doc """
  Get scheduled downlinks for a satellite.
  """
  def get_schedule(satellite_id) do
    GenServer.call(__MODULE__, {:get_schedule, satellite_id})
  end

  @doc """
  Get all active downlink sessions.
  """
  def get_active_sessions do
    GenServer.call(__MODULE__, :get_active_sessions)
  end

  @doc """
  Get downlink statistics.
  """
  def get_stats do
    GenServer.call(__MODULE__, :get_stats)
  end

  @doc """
  Cancel a scheduled downlink.
  """
  def cancel_downlink(downlink_id) do
    GenServer.call(__MODULE__, {:cancel_downlink, downlink_id})
  end

  # ============================================================================
  # Server Callbacks
  # ============================================================================

  @impl true
  def init(_opts) do
    Logger.info("DownlinkScheduler starting")

    # Schedule periodic scheduling check
    :timer.send_interval(@schedule_interval, :check_schedule)

    {:ok, %__MODULE__{}}
  end

  @impl true
  def handle_call({:queue_downlink, satellite_id, data_type, size_bytes, priority, opts}, _from, state) do
    downlink = %{
      id: generate_id(),
      satellite_id: satellite_id,
      data_type: data_type,
      size_bytes: size_bytes,
      priority: priority,
      status: :queued,
      created_at: DateTime.utc_now(),
      scheduled_window: nil,
      ground_station_id: nil,
      metadata: Keyword.get(opts, :metadata, %{})
    }

    scheduled = [downlink | state.scheduled]
    |> Enum.sort_by(& {-&1.priority, &1.created_at})

    Logger.debug("Queued downlink #{downlink.id} for satellite #{satellite_id}")
    {:reply, {:ok, downlink.id}, %{state | scheduled: scheduled}}
  end

  @impl true
  def handle_call({:get_schedule, satellite_id}, _from, state) do
    scheduled = Enum.filter(state.scheduled, &(&1.satellite_id == satellite_id))
    {:reply, scheduled, state}
  end

  @impl true
  def handle_call(:get_active_sessions, _from, state) do
    {:reply, Map.values(state.active), state}
  end

  @impl true
  def handle_call(:get_stats, _from, state) do
    {:reply, state.stats, state}
  end

  @impl true
  def handle_call({:cancel_downlink, downlink_id}, _from, state) do
    case find_downlink(state, downlink_id) do
      nil ->
        {:reply, {:error, :not_found}, state}

      downlink ->
        new_scheduled = Enum.reject(state.scheduled, &(&1.id == downlink_id))
        Logger.info("Cancelled downlink #{downlink_id}")
        {:reply, {:ok, downlink}, %{state | scheduled: new_scheduled}}
    end
  end

  @impl true
  def handle_info(:check_schedule, state) do
    state = schedule_upcoming_windows(state)
    state = check_active_sessions(state)
    {:noreply, state}
  end

  @impl true
  def handle_info({:session_complete, session_id, result}, state) do
    case Map.get(state.active, session_id) do
      nil ->
        {:noreply, state}

      session ->
        stats = case result do
          :success ->
            broadcast_downlink_complete(session)
            %{state.stats |
              completed: state.stats.completed + 1,
              data_transferred_mb: state.stats.data_transferred_mb + (session.size_bytes / 1_048_576)
            }

          :failed ->
            broadcast_downlink_failed(session)
            # Requeue if retries remaining
            maybe_requeue(session, state)
            %{state.stats | failed: state.stats.failed + 1}
        end

        active = Map.delete(state.active, session_id)
        {:noreply, %{state | active: active, stats: stats}}
    end
  end

  # ============================================================================
  # Private Functions
  # ============================================================================

  defp schedule_upcoming_windows(state) do
    now = DateTime.utc_now()
    lookahead_end = DateTime.add(now, @lookahead_minutes * 60, :second)

    # Get upcoming contact windows
    case GroundStations.list_upcoming_contact_windows(now, lookahead_end) do
      windows when is_list(windows) ->
        # Match queued downlinks to windows
        {scheduled, state} = schedule_downlinks_to_windows(state.scheduled, windows, state)
        %{state | scheduled: scheduled}

      _ ->
        state
    end
  end

  defp schedule_downlinks_to_windows(queued, windows, state) do
    Enum.reduce(queued, {[], state}, fn downlink, {remaining, acc_state} ->
      case find_matching_window(downlink, windows) do
        nil ->
          {[downlink | remaining], acc_state}

        window ->
          scheduled_downlink = %{downlink |
            status: :scheduled,
            scheduled_window: window,
            ground_station_id: window.ground_station_id
          }

          # Check if window is starting now
          if window_starting?(window) do
            start_session(scheduled_downlink, acc_state)
            {remaining, acc_state}
          else
            {[scheduled_downlink | remaining], acc_state}
          end
      end
    end)
  end

  defp find_matching_window(downlink, windows) do
    Enum.find(windows, fn window ->
      window.satellite_id == downlink.satellite_id and
        window.status == :scheduled and
        can_fit_downlink?(window, downlink.size_bytes)
    end)
  end

  defp can_fit_downlink?(window, size_bytes) do
    # Calculate available bandwidth during window
    duration_seconds = DateTime.diff(window.los_time, window.aos_time, :second)
    bandwidth_bps = (window.bandwidth_mbps || 10) * 1_000_000

    available_bytes = (duration_seconds * bandwidth_bps / 8) * 0.8  # 80% efficiency
    size_bytes <= available_bytes
  end

  defp window_starting?(window) do
    now = DateTime.utc_now()
    diff = DateTime.diff(window.aos_time, now, :second)
    diff <= 60 and diff >= -60  # Within 1 minute of AOS
  end

  defp start_session(downlink, state) do
    session = %{
      id: downlink.id,
      downlink: downlink,
      started_at: DateTime.utc_now(),
      progress_bytes: 0,
      status: :active
    }

    Logger.info("Starting downlink session #{session.id} for satellite #{downlink.satellite_id}")
    broadcast_downlink_started(session)

    # Simulate session completion (in real system, this would track actual progress)
    # Estimate completion time based on size and bandwidth
    duration_ms = estimate_duration(downlink)
    Process.send_after(self(), {:session_complete, session.id, :success}, duration_ms)

    new_stats = %{state.stats | total: state.stats.total + 1}
    active = Map.put(state.active, session.id, session)

    %{state | active: active, stats: new_stats}
  end

  defp estimate_duration(downlink) do
    # Assume 10 Mbps average bandwidth
    bandwidth_bps = 10_000_000
    size_bits = downlink.size_bytes * 8
    duration_seconds = max(1, Float.ceil(size_bits / bandwidth_bps))
    round(duration_seconds * 1000)
  end

  defp check_active_sessions(state) do
    # Check for stale sessions (shouldn't happen with timers, but just in case)
    now = DateTime.utc_now()
    timeout_seconds = 3600  # 1 hour max session

    {active, timed_out} = Map.split_with(state.active, fn {_id, session} ->
      DateTime.diff(now, session.started_at, :second) < timeout_seconds
    end)

    Enum.each(timed_out, fn {id, session} ->
      Logger.warning("Downlink session #{id} timed out")
      broadcast_downlink_failed(session)
    end)

    %{state | active: active}
  end

  defp maybe_requeue(session, state) do
    retries = Map.get(session.downlink.metadata, :retries, 0)

    if retries < 3 do
      downlink = %{session.downlink |
        status: :queued,
        metadata: Map.put(session.downlink.metadata, :retries, retries + 1)
      }

      Logger.info("Requeuing failed downlink #{session.id} (retry #{retries + 1})")
      %{state | scheduled: [downlink | state.scheduled]}
    else
      Logger.error("Downlink #{session.id} failed after max retries")
      state
    end
  end

  defp find_downlink(state, downlink_id) do
    Enum.find(state.scheduled, &(&1.id == downlink_id))
  end

  defp generate_id do
    :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)
  end

  defp broadcast_downlink_started(session) do
    PubSub.broadcast(@pubsub, "downlinks:updates", {:downlink_started, session})
    PubSub.broadcast(@pubsub, "satellite:#{session.downlink.satellite_id}:downlinks", {:downlink_started, session})
  end

  defp broadcast_downlink_complete(session) do
    PubSub.broadcast(@pubsub, "downlinks:updates", {:downlink_complete, session})
    PubSub.broadcast(@pubsub, "satellite:#{session.downlink.satellite_id}:downlinks", {:downlink_complete, session})
  end

  defp broadcast_downlink_failed(session) do
    PubSub.broadcast(@pubsub, "downlinks:updates", {:downlink_failed, session})
    PubSub.broadcast(@pubsub, "satellite:#{session.downlink.satellite_id}:downlinks", {:downlink_failed, session})
  end
end
