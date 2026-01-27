defmodule StellarCore.Satellite.Server do
  @moduledoc """
  GenServer representing a single satellite.

  Manages satellite state and handles commands like:
  - get_state/1
  - update_energy/2
  - update_memory/2
  - set_mode/2

  Instances are managed by the DynamicSupervisor and registered
  in the Satellite.Registry for lookup by ID.
  """

  use GenServer
  require Logger

  alias StellarCore.Satellite.State
  alias StellarCore.Satellite.Registry
  alias StellarData.Satellites

  # ============================================================================
  # Client API
  # ============================================================================

  @doc """
  Starts a satellite server with the given options.

  Options:
  - :id - Required. The satellite identifier.
  - :name - Optional. Process name (defaults to via tuple using Registry).
  """
  def start_link(opts) do
    id = Keyword.fetch!(opts, :id)
    name = Keyword.get(opts, :name, Registry.via_tuple(id))
    GenServer.start_link(__MODULE__, id, name: name)
  end

  @doc """
  Returns the current state of the satellite.
  """
  @spec get_state(String.t() | pid()) :: State.t()
  def get_state(satellite) do
    GenServer.call(resolve(satellite), :get_state)
  end

  @doc """
  Updates the satellite's energy by the given delta.
  Returns `{:ok, new_state}` with the updated state.
  """
  @spec update_energy(String.t() | pid(), float()) :: {:ok, State.t()}
  def update_energy(satellite, delta) when is_number(delta) do
    GenServer.call(resolve(satellite), {:update_energy, delta / 1})
  end

  @doc """
  Sets the satellite's memory usage.
  Returns `{:ok, new_state}` with the updated state.
  """
  @spec update_memory(String.t() | pid(), float()) :: {:ok, State.t()}
  def update_memory(satellite, memory) when is_number(memory) and memory >= 0 do
    GenServer.call(resolve(satellite), {:update_memory, memory / 1})
  end

  @doc """
  Manually sets the satellite's operational mode.
  Returns `{:ok, new_state}` with the updated state.
  """
  @spec set_mode(String.t() | pid(), State.mode()) :: {:ok, State.t()}
  def set_mode(satellite, mode) when mode in [:nominal, :safe, :survival] do
    GenServer.call(resolve(satellite), {:set_mode, mode})
  end

  @doc """
  Updates the satellite's position.
  Returns `{:ok, new_state}` with the updated state.
  """
  @spec update_position(String.t() | pid(), {float(), float(), float()}) :: {:ok, State.t()}
  def update_position(satellite, {x, y, z})
      when is_number(x) and is_number(y) and is_number(z) do
    GenServer.call(resolve(satellite), {:update_position, {x / 1, y / 1, z / 1}})
  end

  # ============================================================================
  # Server Callbacks
  # ============================================================================

  @impl true
  def init(id) do
    # Set log metadata for this satellite process (observability)
    Logger.metadata(satellite_id: id)
    Logger.info("Satellite started")
    state = State.new(id)
    {:ok, state}
  end

  @impl true
  def handle_call(:get_state, _from, state) do
    {:reply, state, state}
  end

  @impl true
  def handle_call({:update_energy, delta}, _from, state) do
    new_state = State.update_energy(state, delta)
    log_mode_change(state.mode, new_state.mode, state.id)
    # Persist energy change to database
    Satellites.update_satellite_state_by_id(state.id, %{energy: new_state.energy})
    {:reply, {:ok, new_state}, new_state}
  end

  @impl true
  def handle_call({:update_memory, memory}, _from, state) do
    new_state = State.update_memory(state, memory)
    # Persist memory change to database
    Satellites.update_satellite_state_by_id(state.id, %{memory_used: new_state.memory_used})
    {:reply, {:ok, new_state}, new_state}
  end

  @impl true
  def handle_call({:set_mode, mode}, _from, state) do
    new_state = State.set_mode(state, mode)
    log_mode_change(state.mode, new_state.mode, state.id)
    # Persist mode change to database
    Satellites.update_satellite_state_by_id(state.id, %{mode: mode})
    {:reply, {:ok, new_state}, new_state}
  end

  @impl true
  def handle_call({:update_position, position}, _from, state) do
    new_state = State.update_position(state, position)
    {:reply, {:ok, new_state}, new_state}
  end

  # ============================================================================
  # Private Helpers
  # ============================================================================

  defp resolve(pid) when is_pid(pid), do: pid
  defp resolve(id) when is_binary(id), do: Registry.via_tuple(id)

  defp log_mode_change(old_mode, new_mode, _id) when old_mode != new_mode do
    Logger.warning("Mode changed: #{old_mode} -> #{new_mode}")
  end

  defp log_mode_change(_old, _new, _id), do: :ok

  # Child spec for supervision
  def child_spec(opts) do
    id = Keyword.fetch!(opts, :id)

    %{
      id: {__MODULE__, id},
      start: {__MODULE__, :start_link, [opts]},
      restart: :permanent,
      type: :worker
    }
  end
end
