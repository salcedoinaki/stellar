defmodule StellarCore.Satellite.ServerTest do
  use ExUnit.Case, async: true

  alias StellarCore.Satellite.Server
  alias StellarCore.Satellite.State

  # Note: These tests use name: nil to avoid Registry conflicts.
  # Integration tests with Registry are in supervisor_test.exs

  describe "start_link/1" do
    test "starts a satellite server with the given id" do
      {:ok, pid} = Server.start_link(id: "TEST-SAT-001", name: nil)

      assert Process.alive?(pid)

      state = Server.get_state(pid)
      assert state.id == "TEST-SAT-001"

      GenServer.stop(pid)
    end

    test "uses default registry name when name not specified" do
      # This test verifies the via tuple is used correctly
      # We'll test with a unique ID to avoid conflicts
      unique_id = "TEST-SAT-REGISTRY-#{System.unique_integer([:positive])}"
      {:ok, pid} = Server.start_link(id: unique_id)

      assert Process.alive?(pid)
      state = Server.get_state(pid)
      assert state.id == unique_id

      GenServer.stop(pid)
    end
  end

  describe "get_state/1" do
    setup do
      {:ok, pid} = Server.start_link(id: "TEST-SAT-002", name: nil)
      on_exit(fn -> if Process.alive?(pid), do: GenServer.stop(pid) end)
      {:ok, pid: pid}
    end

    test "returns the current state", %{pid: pid} do
      state = Server.get_state(pid)

      assert %State{} = state
      assert state.id == "TEST-SAT-002"
      assert state.mode == :nominal
      assert state.energy == 100.0
    end
  end

  describe "update_energy/2" do
    setup do
      {:ok, pid} = Server.start_link(id: "TEST-SAT-003", name: nil)
      on_exit(fn -> if Process.alive?(pid), do: GenServer.stop(pid) end)
      {:ok, pid: pid}
    end

    test "updates energy level", %{pid: pid} do
      Server.update_energy(pid, -50.0)
      # Give the cast time to process
      :timer.sleep(10)

      state = Server.get_state(pid)
      assert state.energy == 50.0
    end

    test "triggers mode change on low energy", %{pid: pid} do
      Server.update_energy(pid, -85.0)
      :timer.sleep(10)

      state = Server.get_state(pid)
      assert state.energy == 15.0
      assert state.mode == :safe
    end
  end

  describe "update_memory/2" do
    setup do
      {:ok, pid} = Server.start_link(id: "TEST-SAT-004", name: nil)
      on_exit(fn -> if Process.alive?(pid), do: GenServer.stop(pid) end)
      {:ok, pid: pid}
    end

    test "updates memory usage", %{pid: pid} do
      Server.update_memory(pid, 512.0)
      :timer.sleep(10)

      state = Server.get_state(pid)
      assert state.memory_used == 512.0
    end
  end

  describe "set_mode/2" do
    setup do
      {:ok, pid} = Server.start_link(id: "TEST-SAT-005", name: nil)
      on_exit(fn -> if Process.alive?(pid), do: GenServer.stop(pid) end)
      {:ok, pid: pid}
    end

    test "manually sets mode", %{pid: pid} do
      Server.set_mode(pid, :safe)
      :timer.sleep(10)

      state = Server.get_state(pid)
      assert state.mode == :safe
    end
  end

  describe "update_position/2" do
    setup do
      {:ok, pid} = Server.start_link(id: "TEST-SAT-006", name: nil)
      on_exit(fn -> if Process.alive?(pid), do: GenServer.stop(pid) end)
      {:ok, pid: pid}
    end

    test "updates position", %{pid: pid} do
      Server.update_position(pid, {1000.0, 2000.0, 3000.0})
      :timer.sleep(10)

      state = Server.get_state(pid)
      assert state.position == {1000.0, 2000.0, 3000.0}
    end
  end
end
