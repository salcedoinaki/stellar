defmodule StellarCore.Satellite.PropertyTest do
  @moduledoc """
  Property-based tests for satellite state invariants using StreamData.
  """

  use ExUnit.Case, async: true
  use ExUnitProperties

  alias StellarCore.Satellite.State

  # ============================================================================
  # Generators
  # ============================================================================

  defp satellite_id_gen do
    StreamData.string(:alphanumeric, min_length: 3, max_length: 20)
    |> StreamData.map(fn s -> "SAT-#{s}" end)
  end

  defp energy_delta_gen do
    StreamData.float(min: -200.0, max: 200.0)
  end

  defp memory_gen do
    StreamData.float(min: 0.0, max: 4096.0)
  end

  defp position_gen do
    StreamData.tuple({
      StreamData.float(min: -50_000.0, max: 50_000.0),
      StreamData.float(min: -50_000.0, max: 50_000.0),
      StreamData.float(min: -50_000.0, max: 50_000.0)
    })
  end

  defp mode_gen do
    StreamData.member_of([:nominal, :safe, :survival])
  end

  # ============================================================================
  # Property Tests
  # ============================================================================

  describe "State.new/1" do
    property "creates valid state for any valid id" do
      check all id <- satellite_id_gen() do
        state = State.new(id)

        assert state.id == id
        assert state.mode == :nominal
        assert state.energy == 100.0
        assert state.memory_used == 0.0
        assert state.position == {0.0, 0.0, 0.0}
      end
    end
  end

  describe "State.update_energy/2" do
    property "energy is always clamped between 0 and 100" do
      check all id <- satellite_id_gen(),
                delta <- energy_delta_gen() do
        state = State.new(id)
        new_state = State.update_energy(state, delta)

        assert new_state.energy >= 0.0
        assert new_state.energy <= 100.0
      end
    end

    property "multiple energy updates maintain valid bounds" do
      check all id <- satellite_id_gen(),
                deltas <- StreamData.list_of(energy_delta_gen(), min_length: 1, max_length: 20) do
        final_state =
          Enum.reduce(deltas, State.new(id), fn delta, state ->
            State.update_energy(state, delta)
          end)

        assert final_state.energy >= 0.0
        assert final_state.energy <= 100.0
      end
    end

    property "low energy triggers mode transitions" do
      check all id <- satellite_id_gen() do
        state = State.new(id)

        # Drain to critical
        critical_state = State.update_energy(state, -96.0)
        assert critical_state.energy < 5.0
        assert critical_state.mode == :survival

        # Drain to low
        low_state = State.update_energy(state, -85.0)
        assert low_state.energy < 20.0
        assert low_state.mode in [:safe, :survival]
      end
    end
  end

  describe "State.update_memory/2" do
    property "memory is always set to the provided non-negative value" do
      check all id <- satellite_id_gen(),
                memory <- memory_gen() do
        state = State.new(id)
        new_state = State.update_memory(state, memory)

        assert new_state.memory_used == memory
        assert new_state.memory_used >= 0.0
      end
    end
  end

  describe "State.update_position/2" do
    property "position is correctly updated" do
      check all id <- satellite_id_gen(),
                pos <- position_gen() do
        state = State.new(id)
        new_state = State.update_position(state, pos)

        assert new_state.position == pos
      end
    end
  end

  describe "State.set_mode/2" do
    property "mode can be set to any valid mode" do
      check all id <- satellite_id_gen(),
                mode <- mode_gen() do
        state = State.new(id)
        new_state = State.set_mode(state, mode)

        assert new_state.mode == mode
      end
    end
  end

  describe "state immutability" do
    property "updates do not modify original state" do
      check all id <- satellite_id_gen(),
                delta <- energy_delta_gen(),
                memory <- memory_gen(),
                pos <- position_gen() do
        original = State.new(id)

        State.update_energy(original, delta)
        assert original.energy == 100.0

        State.update_memory(original, memory)
        assert original.memory_used == 0.0

        State.update_position(original, pos)
        assert original.position == {0.0, 0.0, 0.0}
      end
    end
  end

  describe "id preservation" do
    property "id is preserved through all state transformations" do
      check all id <- satellite_id_gen(),
                delta <- energy_delta_gen(),
                memory <- memory_gen(),
                mode <- mode_gen(),
                pos <- position_gen() do
        state =
          id
          |> State.new()
          |> State.update_energy(delta)
          |> State.update_memory(memory)
          |> State.set_mode(mode)
          |> State.update_position(pos)

        assert state.id == id
      end
    end
  end
end
