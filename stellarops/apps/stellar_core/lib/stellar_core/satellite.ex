defmodule StellarCore.Satellite do
  @moduledoc """
  Public API for managing satellites in the constellation.

  This module provides a high-level interface for:
  - Starting and stopping satellites
  - Querying satellite state
  - Updating satellite parameters (energy, memory, mode, position)
  - Listing all active satellites

  ## Examples

      # Start a new satellite
      {:ok, pid} = StellarCore.Satellite.start("SAT-001")

      # Get its state
      state = StellarCore.Satellite.get_state("SAT-001")

      # Update energy
      StellarCore.Satellite.update_energy("SAT-001", -10.0)

      # Stop the satellite
      :ok = StellarCore.Satellite.stop("SAT-001")
  """

  alias StellarCore.Satellite.{Server, Supervisor, Registry, State}

  # ============================================================================
  # Lifecycle
  # ============================================================================

  @doc """
  Starts a new satellite with the given ID.

  Returns `{:ok, pid}` on success, `{:error, :already_exists}` if the satellite
  already exists, or `{:error, reason}` for other failures.

  ## Examples

      iex> StellarCore.Satellite.start("SAT-001")
      {:ok, #PID<0.123.0>}
  """
  @spec start(String.t(), keyword()) :: {:ok, pid()} | {:error, term()}
  def start(id, opts \\ []) when is_binary(id) do
    Supervisor.start_satellite(id, opts)
  end

  @doc """
  Stops a satellite by ID.

  Returns `:ok` on success, `{:error, :not_found}` if the satellite doesn't exist.

  ## Examples

      iex> StellarCore.Satellite.stop("SAT-001")
      :ok
  """
  @spec stop(String.t()) :: :ok | {:error, :not_found}
  def stop(id) when is_binary(id) do
    Supervisor.stop_satellite(id)
  end

  @doc """
  Checks if a satellite is running.
  """
  @spec alive?(String.t()) :: boolean()
  def alive?(id) when is_binary(id) do
    Supervisor.satellite_alive?(id)
  end

  @doc """
  Returns the PID for a satellite, or nil if not found.
  """
  @spec whereis(String.t()) :: pid() | nil
  def whereis(id) when is_binary(id) do
    Supervisor.whereis(id)
  end

  # ============================================================================
  # Query
  # ============================================================================

  @doc """
  Returns the current state of a satellite.

  Returns `{:ok, state}` on success, `{:error, :not_found}` if satellite doesn't exist.

  ## Examples

      iex> StellarCore.Satellite.get_state("SAT-001")
      {:ok, %StellarCore.Satellite.State{id: "SAT-001", ...}}
  """
  @spec get_state(String.t()) :: {:ok, State.t()} | {:error, :not_found}
  def get_state(id) when is_binary(id) do
    case Registry.lookup(id) do
      {:ok, _pid} ->
        {:ok, Server.get_state(id)}
      :error ->
        {:error, :not_found}
    end
  end

  @doc """
  Returns the current state of a satellite, raising if not found.

  ## Examples

      iex> state = StellarCore.Satellite.get_state!("SAT-001")
      %StellarCore.Satellite.State{id: "SAT-001", ...}
  """
  @spec get_state!(String.t()) :: State.t()
  def get_state!(id) when is_binary(id) do
    case get_state(id) do
      {:ok, state} -> state
      {:error, :not_found} -> raise "Satellite #{id} not found"
    end
  end

  @doc """
  Safely gets the state of a satellite.

  Returns `{:ok, state}` or `{:error, :not_found}`.

  Deprecated: Use `get_state/1` instead, which now returns the same tuple format.
  """
  @spec fetch_state(String.t()) :: {:ok, State.t()} | {:error, :not_found}
  def fetch_state(id) when is_binary(id) do
    get_state(id)
  end

  @doc """
  Returns a list of all active satellite IDs.
  """
  @spec list() :: [String.t()]
  def list do
    Supervisor.list_satellites()
  end

  @doc """
  Returns the count of active satellites.
  """
  @spec count() :: non_neg_integer()
  def count do
    Supervisor.count_satellites()
  end

  @doc """
  Returns state for all active satellites.
  """
  @spec list_states() :: [State.t()]
  def list_states do
    list()
    |> Enum.map(&get_state!/1)
  end

  # ============================================================================
  # Updates
  # ============================================================================

  @doc """
  Updates a satellite's energy by the given delta.

  Returns `{:ok, :updated}` on success, `{:error, :not_found}` if satellite doesn't exist.

  ## Examples

      iex> StellarCore.Satellite.update_energy("SAT-001", -10.0)
      {:ok, :updated}
  """
  @spec update_energy(String.t(), float()) :: {:ok, :updated} | {:error, :not_found}
  def update_energy(id, delta) when is_binary(id) and is_number(delta) do
    if alive?(id) do
      Server.update_energy(id, delta)
      {:ok, :updated}
    else
      {:error, :not_found}
    end
  end

  @doc """
  Updates a satellite's memory usage.

  Returns `{:ok, :updated}` on success, `{:error, :not_found}` if satellite doesn't exist.

  ## Examples

      iex> StellarCore.Satellite.update_memory("SAT-001", 256.0)
      {:ok, :updated}
  """
  @spec update_memory(String.t(), float()) :: {:ok, :updated} | {:error, :not_found}
  def update_memory(id, memory) when is_binary(id) and is_number(memory) and memory >= 0 do
    if alive?(id) do
      Server.update_memory(id, memory)
      {:ok, :updated}
    else
      {:error, :not_found}
    end
  end

  @doc """
  Sets a satellite's operational mode.

  Valid modes: `:nominal`, `:safe`, `:survival`

  Returns `{:ok, :updated}` on success, `{:error, :not_found}` if satellite doesn't exist.

  ## Examples

      iex> StellarCore.Satellite.set_mode("SAT-001", :safe)
      {:ok, :updated}
  """
  @spec set_mode(String.t(), State.mode()) :: {:ok, :updated} | {:error, :not_found}
  def set_mode(id, mode) when is_binary(id) and mode in [:nominal, :safe, :survival] do
    if alive?(id) do
      Server.set_mode(id, mode)
      {:ok, :updated}
    else
      {:error, :not_found}
    end
  end

  @doc """
  Updates a satellite's position.

  Returns `{:ok, :updated}` on success, `{:error, :not_found}` if satellite doesn't exist.

  ## Examples

      iex> StellarCore.Satellite.update_position("SAT-001", {1000.0, 2000.0, 3000.0})
      {:ok, :updated}
  """
  @spec update_position(String.t(), {number(), number(), number()}) :: {:ok, :updated} | {:error, :not_found}
  def update_position(id, {x, y, z} = position)
      when is_binary(id) and is_number(x) and is_number(y) and is_number(z) do
    if alive?(id) do
      Server.update_position(id, position)
      {:ok, :updated}
    else
      {:error, :not_found}
    end
  end
end
