defmodule StellarCore.Satellite.State do
  @moduledoc """
  Struct representing the state of a satellite.

  Fields:
  - id: unique identifier (e.g., "SAT-001")
  - mode: operational mode (:nominal, :safe, :survival)
  - energy: battery level (0.0 - 100.0)
  - memory_used: memory utilization in MB
  - position: {x, y, z} in ECI coordinates (mock for now)
  """

  @type mode :: :nominal | :safe | :survival

  @type t :: %__MODULE__{
          id: String.t(),
          mode: mode(),
          energy: float(),
          memory_used: float(),
          position: {float(), float(), float()}
        }

  @enforce_keys [:id]
  defstruct [
    :id,
    mode: :nominal,
    energy: 100.0,
    memory_used: 0.0,
    position: {0.0, 0.0, 0.0}
  ]

  @doc """
  Creates a new satellite state with the given id.
  """
  @spec new(String.t()) :: t()
  def new(id) when is_binary(id) do
    %__MODULE__{id: id}
  end

  @doc """
  Updates the energy level, clamping between 0 and 100.
  Automatically transitions to :safe mode if energy < 20,
  and :survival mode if energy < 5.
  """
  @spec update_energy(t(), float()) :: t()
  def update_energy(%__MODULE__{} = state, delta) do
    new_energy = max(0.0, min(100.0, state.energy + delta))
    new_mode = determine_mode(new_energy, state.mode)
    %{state | energy: new_energy, mode: new_mode}
  end

  @doc """
  Updates memory usage.
  """
  @spec update_memory(t(), float()) :: t()
  def update_memory(%__MODULE__{} = state, memory) when memory >= 0 do
    %{state | memory_used: memory}
  end

  @doc """
  Updates the satellite position.
  """
  @spec update_position(t(), {float(), float(), float()}) :: t()
  def update_position(%__MODULE__{} = state, {x, y, z} = pos)
      when is_float(x) and is_float(y) and is_float(z) do
    %{state | position: pos}
  end

  @doc """
  Manually set mode (for commands like entering safe mode).
  """
  @spec set_mode(t(), mode()) :: t()
  def set_mode(%__MODULE__{} = state, mode) when mode in [:nominal, :safe, :survival] do
    %{state | mode: mode}
  end

  # Private helpers

  defp determine_mode(energy, current_mode) do
    cond do
      energy < 5.0 -> :survival
      energy < 20.0 -> :safe
      current_mode == :survival and energy >= 10.0 -> :safe
      current_mode == :safe and energy >= 30.0 -> :nominal
      true -> current_mode
    end
  end
end
