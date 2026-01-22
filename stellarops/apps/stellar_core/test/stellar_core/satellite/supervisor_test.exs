defmodule StellarCore.Satellite.SupervisorTest do
  use ExUnit.Case, async: false

  alias StellarCore.Satellite
  alias StellarCore.Satellite.{Supervisor, Registry}

  # We use async: false because we're testing the application's
  # DynamicSupervisor which is shared state

  setup do
    # Clean up any satellites from previous tests
    for id <- Satellite.list() do
      Satellite.stop(id)
    end

    :ok
  end

  describe "start_satellite/2" do
    test "starts a satellite and registers it" do
      assert {:ok, pid} = Supervisor.start_satellite("TEST-SUP-001")
      assert is_pid(pid)
      assert Process.alive?(pid)

      # Verify it's registered
      assert {:ok, ^pid} = Registry.lookup("TEST-SUP-001")

      # Clean up
      Supervisor.stop_satellite("TEST-SUP-001")
    end

    test "returns error when starting duplicate satellite" do
      {:ok, _pid} = Supervisor.start_satellite("TEST-SUP-002")
      assert {:error, :already_exists} = Supervisor.start_satellite("TEST-SUP-002")

      # Clean up
      Supervisor.stop_satellite("TEST-SUP-002")
    end
  end

  describe "stop_satellite/1" do
    test "stops a running satellite" do
      {:ok, pid} = Supervisor.start_satellite("TEST-SUP-003")
      assert Process.alive?(pid)

      assert :ok = Supervisor.stop_satellite("TEST-SUP-003")

      # Give it a moment to terminate
      :timer.sleep(10)
      refute Process.alive?(pid)
      assert :error = Registry.lookup("TEST-SUP-003")
    end

    test "returns error for non-existent satellite" do
      assert {:error, :not_found} = Supervisor.stop_satellite("NONEXISTENT")
    end
  end

  describe "list_satellites/0" do
    test "lists all active satellites" do
      {:ok, _} = Supervisor.start_satellite("TEST-SUP-004")
      {:ok, _} = Supervisor.start_satellite("TEST-SUP-005")
      {:ok, _} = Supervisor.start_satellite("TEST-SUP-006")

      ids = Supervisor.list_satellites()
      assert "TEST-SUP-004" in ids
      assert "TEST-SUP-005" in ids
      assert "TEST-SUP-006" in ids

      # Clean up
      Supervisor.stop_satellite("TEST-SUP-004")
      Supervisor.stop_satellite("TEST-SUP-005")
      Supervisor.stop_satellite("TEST-SUP-006")
    end
  end

  describe "count_satellites/0" do
    test "count increases and decreases with satellites" do
      # Use unique prefixes to avoid conflicts with other tests
      unique1 = "COUNT-TEST-#{System.unique_integer([:positive])}"
      unique2 = "COUNT-TEST-#{System.unique_integer([:positive])}"
      
      count_before = Supervisor.count_satellites()

      {:ok, _} = Supervisor.start_satellite(unique1)
      {:ok, _} = Supervisor.start_satellite(unique2)

      count_after = Supervisor.count_satellites()
      assert count_after >= count_before + 2

      Supervisor.stop_satellite(unique1)
      :timer.sleep(10)
      count_after_one_stop = Supervisor.count_satellites()
      assert count_after_one_stop == count_after - 1

      Supervisor.stop_satellite(unique2)
      :timer.sleep(10)
      count_final = Supervisor.count_satellites()
      assert count_final == count_after - 2
    end
  end

  describe "whereis/1" do
    test "returns PID for existing satellite" do
      {:ok, pid} = Supervisor.start_satellite("TEST-SUP-009")
      assert Supervisor.whereis("TEST-SUP-009") == pid

      Supervisor.stop_satellite("TEST-SUP-009")
    end

    test "returns nil for non-existent satellite" do
      assert Supervisor.whereis("NONEXISTENT") == nil
    end
  end

  describe "satellite_alive?/1" do
    test "returns true for running satellite" do
      {:ok, _pid} = Supervisor.start_satellite("TEST-SUP-010")
      assert Supervisor.satellite_alive?("TEST-SUP-010")

      Supervisor.stop_satellite("TEST-SUP-010")
    end

    test "returns false for non-existent satellite" do
      refute Supervisor.satellite_alive?("NONEXISTENT")
    end
  end

  describe "auto-restart behavior" do
    test "satellite is automatically restarted when killed" do
      {:ok, original_pid} = Supervisor.start_satellite("TEST-SUP-011")
      assert Process.alive?(original_pid)

      # Kill the process
      Process.exit(original_pid, :kill)

      # Give the supervisor time to restart
      :timer.sleep(50)

      # Satellite should be restarted with new PID
      assert Supervisor.satellite_alive?("TEST-SUP-011")
      new_pid = Supervisor.whereis("TEST-SUP-011")
      assert is_pid(new_pid)
      assert new_pid != original_pid
      assert Process.alive?(new_pid)

      Supervisor.stop_satellite("TEST-SUP-011")
    end

    test "spawning 10 satellites, killing one, and verifying restart" do
      # Spawn 10 satellites
      satellite_ids =
        for i <- 1..10 do
          id = "BATCH-SAT-#{String.pad_leading(Integer.to_string(i), 3, "0")}"
          {:ok, _pid} = Supervisor.start_satellite(id)
          id
        end

      # Verify all 10 are running
      assert length(Supervisor.list_satellites() |> Enum.filter(&String.starts_with?(&1, "BATCH-SAT"))) == 10

      # Kill the 5th satellite
      target_id = "BATCH-SAT-005"
      original_pid = Supervisor.whereis(target_id)
      Process.exit(original_pid, :kill)

      # Give the supervisor time to restart
      :timer.sleep(50)

      # Verify all 10 are still running (one was restarted)
      running_satellites =
        Supervisor.list_satellites()
        |> Enum.filter(&String.starts_with?(&1, "BATCH-SAT"))

      assert length(running_satellites) == 10

      # Verify the killed one was restarted with a new PID
      new_pid = Supervisor.whereis(target_id)
      assert new_pid != original_pid
      assert Process.alive?(new_pid)

      # Clean up
      for id <- satellite_ids do
        Supervisor.stop_satellite(id)
      end
    end
  end

  describe "registry lookup after restart (TASK-037)" do
    test "registry correctly tracks satellite after supervisor restart" do
      # Start a satellite
      {:ok, original_pid} = Supervisor.start_satellite("REG-RESTART-001")
      assert {:ok, ^original_pid} = Registry.lookup("REG-RESTART-001")

      # Kill the satellite to trigger restart
      Process.exit(original_pid, :kill)
      :timer.sleep(50)

      # Registry should have the new PID
      {:ok, new_pid} = Registry.lookup("REG-RESTART-001")
      assert is_pid(new_pid)
      assert new_pid != original_pid
      assert Process.alive?(new_pid)

      Supervisor.stop_satellite("REG-RESTART-001")
    end

    test "registry is empty after satellite is stopped" do
      {:ok, _pid} = Supervisor.start_satellite("REG-RESTART-002")
      assert {:ok, _} = Registry.lookup("REG-RESTART-002")

      Supervisor.stop_satellite("REG-RESTART-002")
      :timer.sleep(10)

      assert :error = Registry.lookup("REG-RESTART-002")
    end
  end

  describe "supervisor restart strategy (TASK-036)" do
    test "supervisor uses one_for_one strategy - other satellites unaffected" do
      # Start multiple satellites
      {:ok, pid1} = Supervisor.start_satellite("STRATEGY-001")
      {:ok, pid2} = Supervisor.start_satellite("STRATEGY-002")
      {:ok, pid3} = Supervisor.start_satellite("STRATEGY-003")

      # Kill one satellite
      Process.exit(pid2, :kill)
      :timer.sleep(50)

      # Other satellites should be unaffected (same PID)
      assert Supervisor.whereis("STRATEGY-001") == pid1
      assert Supervisor.whereis("STRATEGY-003") == pid3
      assert Process.alive?(pid1)
      assert Process.alive?(pid3)

      # The killed one should have a new PID
      new_pid2 = Supervisor.whereis("STRATEGY-002")
      assert new_pid2 != pid2
      assert Process.alive?(new_pid2)

      # Clean up
      Supervisor.stop_satellite("STRATEGY-001")
      Supervisor.stop_satellite("STRATEGY-002")
      Supervisor.stop_satellite("STRATEGY-003")
    end
  end
end
