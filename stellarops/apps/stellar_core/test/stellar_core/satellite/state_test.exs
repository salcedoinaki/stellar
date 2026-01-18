defmodule StellarCore.Satellite.StateTest do
  use ExUnit.Case, async: true

  alias StellarCore.Satellite.State

  describe "new/1" do
    test "creates a satellite state with default values" do
      state = State.new("SAT-001")

      assert state.id == "SAT-001"
      assert state.mode == :nominal
      assert state.energy == 100.0
      assert state.memory_used == 0.0
      assert state.position == {0.0, 0.0, 0.0}
    end
  end

  describe "update_energy/2" do
    test "increases energy" do
      state = %State{id: "SAT-001", energy: 50.0}
      updated = State.update_energy(state, 10.0)

      assert updated.energy == 60.0
    end

    test "decreases energy" do
      state = %State{id: "SAT-001", energy: 50.0}
      updated = State.update_energy(state, -10.0)

      assert updated.energy == 40.0
    end

    test "clamps energy at 0" do
      state = %State{id: "SAT-001", energy: 10.0}
      updated = State.update_energy(state, -20.0)

      assert updated.energy == 0.0
    end

    test "clamps energy at 100" do
      state = %State{id: "SAT-001", energy: 95.0}
      updated = State.update_energy(state, 10.0)

      assert updated.energy == 100.0
    end

    test "transitions to safe mode when energy drops below 20" do
      state = %State{id: "SAT-001", energy: 25.0, mode: :nominal}
      updated = State.update_energy(state, -10.0)

      assert updated.energy == 15.0
      assert updated.mode == :safe
    end

    test "transitions to survival mode when energy drops below 5" do
      state = %State{id: "SAT-001", energy: 10.0, mode: :safe}
      updated = State.update_energy(state, -8.0)

      assert updated.energy == 2.0
      assert updated.mode == :survival
    end

    test "transitions from survival to safe when energy recovers above 10" do
      state = %State{id: "SAT-001", energy: 5.0, mode: :survival}
      updated = State.update_energy(state, 10.0)

      assert updated.energy == 15.0
      assert updated.mode == :safe
    end

    test "transitions from safe to nominal when energy recovers above 30" do
      state = %State{id: "SAT-001", energy: 25.0, mode: :safe}
      updated = State.update_energy(state, 10.0)

      assert updated.energy == 35.0
      assert updated.mode == :nominal
    end
  end

  describe "update_memory/2" do
    test "updates memory usage" do
      state = State.new("SAT-001")
      updated = State.update_memory(state, 256.0)

      assert updated.memory_used == 256.0
    end
  end

  describe "update_position/2" do
    test "updates position" do
      state = State.new("SAT-001")
      updated = State.update_position(state, {1000.0, 2000.0, 3000.0})

      assert updated.position == {1000.0, 2000.0, 3000.0}
    end
  end

  describe "set_mode/2" do
    test "sets mode to safe" do
      state = State.new("SAT-001")
      updated = State.set_mode(state, :safe)

      assert updated.mode == :safe
    end

    test "sets mode to survival" do
      state = State.new("SAT-001")
      updated = State.set_mode(state, :survival)

      assert updated.mode == :survival
    end
  end
end
