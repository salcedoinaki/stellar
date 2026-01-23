defmodule StellarCore.Satellite.IntegrationTest do
  @moduledoc """
  Integration tests for satellite lifecycle and concurrent access.
  
  TASK-028: Integration tests for satellite lifecycle (start → update → stop)
  TASK-029: Tests for concurrent access to satellite state
  TASK-030: Tests for satellite restart after crash (also in supervisor_test.exs)
  """

  use ExUnit.Case, async: false

  alias StellarCore.Satellite
  alias StellarCore.Satellite.State

  setup do
    # Clean up any satellites from previous tests
    for id <- Satellite.list() do
      Satellite.stop(id)
    end

    :ok
  end

  describe "satellite lifecycle (TASK-028)" do
    test "complete lifecycle: start → get_state → updates → stop" do
      # Start
      assert {:ok, pid} = Satellite.start("LIFECYCLE-001")
      assert is_pid(pid)
      assert Process.alive?(pid)

      # Get initial state
      assert {:ok, state} = Satellite.get_state("LIFECYCLE-001")
      assert %State{} = state
      assert state.id == "LIFECYCLE-001"
      assert state.mode == :nominal
      assert state.energy == 100.0
      assert state.memory_used == 0.0

      # Update energy
      assert {:ok, state2} = Satellite.update_energy("LIFECYCLE-001", -25.0)
      assert state2.energy == 75.0

      # Update memory
      assert {:ok, state3} = Satellite.update_memory("LIFECYCLE-001", 128.0)
      assert state3.memory_used == 128.0

      # Set mode
      assert {:ok, state4} = Satellite.set_mode("LIFECYCLE-001", :safe)
      assert state4.mode == :safe

      # Update position
      assert {:ok, state5} = Satellite.update_position("LIFECYCLE-001", {100.0, 200.0, 300.0})
      assert state5.position == {100.0, 200.0, 300.0}

      # Verify all changes persisted
      assert {:ok, final_state} = Satellite.get_state("LIFECYCLE-001")
      assert final_state.energy == 75.0
      assert final_state.memory_used == 128.0
      assert final_state.mode == :safe
      assert final_state.position == {100.0, 200.0, 300.0}

      # Stop
      assert :ok = Satellite.stop("LIFECYCLE-001")
      :timer.sleep(10)
      refute Satellite.alive?("LIFECYCLE-001")
      assert {:error, :not_found} = Satellite.get_state("LIFECYCLE-001")
    end

    test "lifecycle with mode transitions from energy changes" do
      {:ok, _} = Satellite.start("LIFECYCLE-002")

      # Drain energy to trigger safe mode (< 20%)
      {:ok, state} = Satellite.update_energy("LIFECYCLE-002", -85.0)
      assert state.energy == 15.0
      assert state.mode == :safe

      # Drain more to trigger survival mode (< 5%)
      {:ok, state2} = Satellite.update_energy("LIFECYCLE-002", -12.0)
      assert state2.energy == 3.0
      assert state2.mode == :survival

      # Recover energy
      {:ok, state3} = Satellite.update_energy("LIFECYCLE-002", 50.0)
      assert state3.energy == 53.0
      assert state3.mode == :nominal

      Satellite.stop("LIFECYCLE-002")
    end

    test "multiple satellites can be managed independently" do
      # Start 5 satellites
      sat_ids = for i <- 1..5, do: "MULTI-#{i}"
      
      for id <- sat_ids do
        {:ok, _} = Satellite.start(id)
      end

      # Update each differently
      {:ok, _} = Satellite.update_energy("MULTI-1", -10.0)
      {:ok, _} = Satellite.update_energy("MULTI-2", -20.0)
      {:ok, _} = Satellite.update_energy("MULTI-3", -30.0)
      {:ok, _} = Satellite.set_mode("MULTI-4", :safe)
      {:ok, _} = Satellite.update_memory("MULTI-5", 512.0)

      # Verify each has independent state
      {:ok, s1} = Satellite.get_state("MULTI-1")
      {:ok, s2} = Satellite.get_state("MULTI-2")
      {:ok, s3} = Satellite.get_state("MULTI-3")
      {:ok, s4} = Satellite.get_state("MULTI-4")
      {:ok, s5} = Satellite.get_state("MULTI-5")

      assert s1.energy == 90.0
      assert s2.energy == 80.0
      assert s3.energy == 70.0
      assert s4.mode == :safe
      assert s5.memory_used == 512.0

      # Stop all
      for id <- sat_ids, do: Satellite.stop(id)
    end
  end

  describe "concurrent access (TASK-029)" do
    test "concurrent energy updates are handled correctly" do
      {:ok, _} = Satellite.start("CONCURRENT-001")

      # Spawn multiple processes to update energy concurrently
      tasks =
        for i <- 1..10 do
          Task.async(fn ->
            Satellite.update_energy("CONCURRENT-001", -5.0)
            i
          end)
        end

      # Wait for all tasks to complete
      results = Task.await_many(tasks, 5000)
      assert length(results) == 10

      # Final energy should be 100 - (10 * 5) = 50
      {:ok, state} = Satellite.get_state("CONCURRENT-001")
      assert state.energy == 50.0

      Satellite.stop("CONCURRENT-001")
    end

    test "concurrent reads do not block each other" do
      {:ok, _} = Satellite.start("CONCURRENT-002")

      # Spawn 20 concurrent readers
      tasks =
        for _ <- 1..20 do
          Task.async(fn ->
            {:ok, state} = Satellite.get_state("CONCURRENT-002")
            state.id
          end)
        end

      results = Task.await_many(tasks, 5000)
      assert Enum.all?(results, &(&1 == "CONCURRENT-002"))

      Satellite.stop("CONCURRENT-002")
    end

    test "concurrent reads and writes are serialized correctly" do
      {:ok, _} = Satellite.start("CONCURRENT-003")

      # Mix of reads and writes
      tasks =
        for i <- 1..20 do
          Task.async(fn ->
            if rem(i, 2) == 0 do
              {:ok, _} = Satellite.update_energy("CONCURRENT-003", -1.0)
              :write
            else
              {:ok, _} = Satellite.get_state("CONCURRENT-003")
              :read
            end
          end)
        end

      results = Task.await_many(tasks, 5000)
      writes = Enum.count(results, &(&1 == :write))
      reads = Enum.count(results, &(&1 == :read))

      assert writes == 10
      assert reads == 10

      # Final energy should be 100 - 10 = 90
      {:ok, state} = Satellite.get_state("CONCURRENT-003")
      assert state.energy == 90.0

      Satellite.stop("CONCURRENT-003")
    end

    test "concurrent operations on multiple satellites" do
      # Start 5 satellites
      sat_ids = for i <- 1..5, do: "CONCURRENT-MULTI-#{i}"
      for id <- sat_ids, do: {:ok, _} = Satellite.start(id)

      # Each satellite gets 4 concurrent updates
      tasks =
        for id <- sat_ids, _ <- 1..4 do
          Task.async(fn ->
            {:ok, _} = Satellite.update_energy(id, -5.0)
            id
          end)
        end

      results = Task.await_many(tasks, 5000)
      assert length(results) == 20

      # Each satellite should have energy = 100 - (4 * 5) = 80
      for id <- sat_ids do
        {:ok, state} = Satellite.get_state(id)
        assert state.energy == 80.0
      end

      for id <- sat_ids, do: Satellite.stop(id)
    end
  end

  describe "restart after crash (TASK-030)" do
    test "satellite state is reset after crash and restart" do
      {:ok, pid} = Satellite.start("CRASH-001")

      # Modify state
      {:ok, _} = Satellite.update_energy("CRASH-001", -50.0)
      {:ok, state_before} = Satellite.get_state("CRASH-001")
      assert state_before.energy == 50.0

      # Crash the satellite
      Process.exit(pid, :kill)
      :timer.sleep(50)

      # Satellite should be restarted with fresh state
      assert Satellite.alive?("CRASH-001")
      {:ok, state_after} = Satellite.get_state("CRASH-001")
      
      # State is reset to defaults on restart
      assert state_after.energy == 100.0
      assert state_after.mode == :nominal

      Satellite.stop("CRASH-001")
    end

    test "operations on restarted satellite work normally" do
      {:ok, pid} = Satellite.start("CRASH-002")
      Process.exit(pid, :kill)
      :timer.sleep(50)

      # Should be able to perform operations on restarted satellite
      assert {:ok, state} = Satellite.update_energy("CRASH-002", -30.0)
      assert state.energy == 70.0

      assert {:ok, state2} = Satellite.set_mode("CRASH-002", :safe)
      assert state2.mode == :safe

      Satellite.stop("CRASH-002")
    end
  end
end
