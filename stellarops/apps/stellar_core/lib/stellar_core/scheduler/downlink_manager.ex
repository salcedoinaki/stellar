defmodule StellarCore.Scheduler.DownlinkManager do
  @moduledoc """
  GenServer for managing satellite downlink windows and bandwidth allocation.

  Responsibilities:
  - Track contact windows between satellites and ground stations
  - Allocate bandwidth for downlink missions
  - Activate windows when passes begin
  - Collect data transfer statistics
  - Generate upcoming window predictions
  """

  use GenServer
  require Logger

  alias StellarData.GroundStations
  alias StellarData.GroundStations.ContactWindow

  @window_check_interval :timer.seconds(10)
  @prediction_horizon_hours 24

  # ============================================================================
  # Client API
  # ============================================================================

  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Requests bandwidth allocation for a satellite downlink.

  Returns {:ok, window} if allocation succeeded, {:error, reason} otherwise.
  """
  def request_downlink(satellite_id, required_bandwidth, opts \\ [], server \\ __MODULE__) do
    GenServer.call(server, {:request_downlink, satellite_id, required_bandwidth, opts})
  end

  @doc """
  Gets upcoming contact windows for a satellite.
  """
  def get_upcoming_windows(satellite_id, limit \\ 5, server \\ __MODULE__) do
    GenServer.call(server, {:get_upcoming_windows, satellite_id, limit})
  end

  @doc """
  Gets currently active contact windows.
  """
  def get_active_windows(server \\ __MODULE__) do
    GenServer.call(server, :get_active_windows)
  end

  @doc """
  Gets total available bandwidth across all online ground stations.
  """
  def available_bandwidth(server \\ __MODULE__) do
    GenServer.call(server, :available_bandwidth)
  end

  @doc """
  Manually activates a contact window.
  """
  def activate_window(window_id, server \\ __MODULE__) do
    GenServer.call(server, {:activate_window, window_id})
  end

  @doc """
  Reports data transferred during a window.
  """
  def report_transfer(window_id, data_mb, server \\ __MODULE__) do
    GenServer.cast(server, {:report_transfer, window_id, data_mb})
  end

  @doc """
  Gets downlink statistics.
  """
  def stats(server \\ __MODULE__) do
    GenServer.call(server, :stats)
  end

  # ============================================================================
  # Server Callbacks
  # ============================================================================

  @impl true
  def init(opts) do
    Logger.info("Starting Downlink Manager")

    state = %{
      check_interval: Keyword.get(opts, :check_interval, @window_check_interval),
      active_windows: %{},  # window_id => %{started_at, allocated_bandwidth}
      stats: %{
        windows_completed: 0,
        total_data_mb: 0.0,
        allocations: 0
      }
    }

    # Schedule window check
    schedule_check(state)

    {:ok, state}
  end

  @impl true
  def handle_call({:request_downlink, satellite_id, required_bandwidth, opts}, _from, state) do
    deadline = Keyword.get(opts, :deadline)
    min_duration = Keyword.get(opts, :min_duration, 60)

    case GroundStations.find_best_window(satellite_id,
           deadline: deadline,
           min_bandwidth: required_bandwidth,
           min_duration: min_duration
         ) do
      nil ->
        {:reply, {:error, :no_available_window}, state}

      window ->
        case GroundStations.allocate_bandwidth(window, required_bandwidth) do
          {:ok, allocated_window} ->
            Logger.info(
              "Allocated #{required_bandwidth} Mbps on window #{window.id} " <>
                "for satellite #{satellite_id}"
            )

            new_state = update_in(state.stats.allocations, &(&1 + 1))
            broadcast_event(:bandwidth_allocated, allocated_window)
            {:reply, {:ok, allocated_window}, new_state}

          {:error, reason} ->
            {:reply, {:error, reason}, state}
        end
    end
  end

  @impl true
  def handle_call({:get_upcoming_windows, satellite_id, limit}, _from, state) do
    windows = GroundStations.get_upcoming_windows(satellite_id, limit)
    {:reply, windows, state}
  end

  @impl true
  def handle_call(:get_active_windows, _from, state) do
    windows = GroundStations.get_active_windows()
    {:reply, windows, state}
  end

  @impl true
  def handle_call(:available_bandwidth, _from, state) do
    bandwidth = GroundStations.total_available_bandwidth()
    {:reply, bandwidth, state}
  end

  @impl true
  def handle_call({:activate_window, window_id}, _from, state) do
    case GroundStations.get_contact_window(window_id) do
      nil ->
        {:reply, {:error, :not_found}, state}

      window ->
        case GroundStations.activate_window(window) do
          {:ok, activated} ->
            new_state =
              put_in(state.active_windows[window_id], %{
                started_at: DateTime.utc_now(),
                allocated_bandwidth: window.allocated_bandwidth
              })

            broadcast_event(:window_activated, activated)
            {:reply, {:ok, activated}, new_state}

          {:error, reason} ->
            {:reply, {:error, reason}, state}
        end
    end
  end

  @impl true
  def handle_call(:stats, _from, state) do
    {:reply, state.stats, state}
  end

  @impl true
  def handle_cast({:report_transfer, window_id, data_mb}, state) do
    case GroundStations.get_contact_window(window_id) do
      nil ->
        {:noreply, state}

      window ->
        {:ok, completed} = GroundStations.complete_window(window, data_mb)

        new_state =
          state
          |> Map.update!(:active_windows, &Map.delete(&1, window_id))
          |> update_in([:stats, :windows_completed], &(&1 + 1))
          |> update_in([:stats, :total_data_mb], &(&1 + data_mb))

        Logger.info("Window #{window_id} completed: #{data_mb} MB transferred")
        broadcast_event(:window_completed, completed)
        {:noreply, new_state}
    end
  end

  @impl true
  def handle_info(:check_windows, state) do
    new_state = check_window_transitions(state)
    schedule_check(state)
    {:noreply, new_state}
  end

  # ============================================================================
  # Window Management
  # ============================================================================

  defp check_window_transitions(state) do
    now = DateTime.utc_now()

    # Check for windows that should be activated
    state =
      GroundStations.get_active_windows()
      |> Enum.filter(&(&1.status == :scheduled))
      |> Enum.reduce(state, fn window, acc ->
        if DateTime.compare(window.aos, now) != :gt do
          # Window should be active
          {:ok, activated} = GroundStations.activate_window(window)

          acc
          |> put_in([:active_windows, window.id], %{
            started_at: now,
            allocated_bandwidth: window.allocated_bandwidth
          })
          |> tap(fn _ -> broadcast_event(:window_activated, activated) end)
        else
          acc
        end
      end)

    # Check for windows that have ended
    Enum.reduce(state.active_windows, state, fn {window_id, _info}, acc ->
      case GroundStations.get_contact_window(window_id) do
        nil ->
          update_in(acc.active_windows, &Map.delete(&1, window_id))

        window ->
          if DateTime.compare(window.los, now) == :lt do
            # Window has ended without explicit completion - mark as missed
            Logger.warning("Window #{window_id} ended without data transfer report")
            update_in(acc.active_windows, &Map.delete(&1, window_id))
          else
            acc
          end
      end
    end)
  end

  # ============================================================================
  # Helpers
  # ============================================================================

  defp schedule_check(%{check_interval: interval}) do
    Process.send_after(self(), :check_windows, interval)
  end

  defp broadcast_event(event, window) do
    Phoenix.PubSub.broadcast(
      StellarWeb.PubSub,
      "downlink:events",
      {event, window}
    )
  end
end
