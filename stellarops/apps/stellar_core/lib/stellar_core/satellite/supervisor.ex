defmodule StellarCore.Satellite.Supervisor do
  @moduledoc """
  DynamicSupervisor for managing multiple satellite GenServers.

  Provides functions to dynamically start and stop satellite processes.
  Each satellite is registered in the Satellite.Registry for lookup by ID.

  ## Resilience

  The supervisor uses `:one_for_one` strategy, meaning if a satellite crashes,
  only that satellite is restarted. Other satellites continue unaffected.
  """

  use DynamicSupervisor
  require Logger

  alias StellarCore.Satellite.Server
  alias StellarCore.Satellite.Registry

  @supervisor_name __MODULE__

  # ============================================================================
  # Client API
  # ============================================================================

  @doc """
  Starts the DynamicSupervisor.
  """
  def start_link(init_arg) do
    DynamicSupervisor.start_link(__MODULE__, init_arg, name: @supervisor_name)
  end

  @doc """
  Starts a new satellite with the given ID.

  Returns `{:ok, pid}` if successful, `{:error, reason}` otherwise.
  If a satellite with the same ID already exists, returns `{:error, :already_exists}`.

  ## Options

  - `:id` - Required. The unique satellite identifier.
  - `:energy` - Optional. Initial energy level (default: 100.0).
  - `:mode` - Optional. Initial mode (default: :nominal).

  ## Examples

      iex> StellarCore.Satellite.Supervisor.start_satellite("SAT-001")
      {:ok, #PID<0.123.0>}

      iex> StellarCore.Satellite.Supervisor.start_satellite("SAT-001")
      {:error, :already_exists}
  """
  @spec start_satellite(String.t(), keyword()) :: {:ok, pid()} | {:error, term()}
  def start_satellite(id, opts \\ []) when is_binary(id) do
    case Registry.lookup(id) do
      {:ok, _pid} ->
        {:error, :already_exists}

      :error ->
        child_spec = {Server, Keyword.put(opts, :id, id)}

        Logger.info("Starting satellite",
          satellite_id: id,
          satellite_opts: inspect(opts)
        )

        DynamicSupervisor.start_child(@supervisor_name, child_spec)
    end
  end

  @doc """
  Stops a satellite by ID.

  Returns `:ok` if the satellite was stopped, `{:error, :not_found}` if not found.

  ## Examples

      iex> StellarCore.Satellite.Supervisor.stop_satellite("SAT-001")
      :ok

      iex> StellarCore.Satellite.Supervisor.stop_satellite("SAT-999")
      {:error, :not_found}
  """
  @spec stop_satellite(String.t()) :: :ok | {:error, :not_found}
  def stop_satellite(id) when is_binary(id) do
    case Registry.lookup(id) do
      {:ok, pid} ->
        Logger.info("Stopping satellite", satellite_id: id)
        DynamicSupervisor.terminate_child(@supervisor_name, pid)

      :error ->
        {:error, :not_found}
    end
  end

  @doc """
  Returns a list of all active satellite IDs.
  """
  @spec list_satellites() :: [String.t()]
  def list_satellites do
    Registry.list_ids()
  end

  @doc """
  Returns the number of active satellites.
  """
  @spec count_satellites() :: non_neg_integer()
  def count_satellites do
    Registry.count()
  end

  @doc """
  Returns the PID for a satellite by ID, or nil if not found.
  """
  @spec whereis(String.t()) :: pid() | nil
  def whereis(id) when is_binary(id) do
    case Registry.lookup(id) do
      {:ok, pid} -> pid
      :error -> nil
    end
  end

  @doc """
  Checks if a satellite with the given ID is running.
  """
  @spec satellite_alive?(String.t()) :: boolean()
  def satellite_alive?(id) when is_binary(id) do
    case Registry.lookup(id) do
      {:ok, pid} -> Process.alive?(pid)
      :error -> false
    end
  end

  # ============================================================================
  # Supervisor Callbacks
  # ============================================================================

  @impl true
  def init(_init_arg) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  @doc """
  Returns the supervisor name for testing and introspection.
  """
  def supervisor_name, do: @supervisor_name
end
