defmodule StellarCore.SatelliteTest do
  @moduledoc """
  Tests for the public Satellite API.
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

  describe "start/2 and stop/1" do
    test "starts and stops a satellite" do
      assert {:ok, pid} = Satellite.start("API-TEST-001")
      assert is_pid(pid)
      assert Process.alive?(pid)

      assert :ok = Satellite.stop("API-TEST-001")
      :timer.sleep(10)
      refute Process.alive?(pid)
    end

    test "returns error when starting duplicate" do
      {:ok, _} = Satellite.start("API-TEST-002")
      assert {:error, :already_exists} = Satellite.start("API-TEST-002")

      Satellite.stop("API-TEST-002")
    end
  end

  describe "alive?/1 and whereis/1" do
    test "alive? returns true for running satellite" do
      {:ok, _} = Satellite.start("API-TEST-003")
      assert Satellite.alive?("API-TEST-003")

      Satellite.stop("API-TEST-003")
    end

    test "alive? returns false for non-existent satellite" do
      refute Satellite.alive?("NONEXISTENT")
    end

    test "whereis returns PID or nil" do
      {:ok, pid} = Satellite.start("API-TEST-004")
      assert Satellite.whereis("API-TEST-004") == pid

      Satellite.stop("API-TEST-004")
      :timer.sleep(10)
      assert Satellite.whereis("API-TEST-004") == nil
    end
  end

  describe "get_state/1 and fetch_state/1" do
    test "get_state returns {:ok, state} tuple" do
      {:ok, _} = Satellite.start("API-TEST-005")

      assert {:ok, state} = Satellite.get_state("API-TEST-005")
      assert %State{} = state
      assert state.id == "API-TEST-005"
      assert state.mode == :nominal
      assert state.energy == 100.0

      Satellite.stop("API-TEST-005")
    end

    test "get_state returns {:error, :not_found} for non-existent satellite" do
      assert {:error, :not_found} = Satellite.get_state("NONEXISTENT")
    end

    test "fetch_state returns {:ok, state} or {:error, :not_found}" do
      {:ok, _} = Satellite.start("API-TEST-006")

      assert {:ok, %State{id: "API-TEST-006"}} = Satellite.fetch_state("API-TEST-006")
      assert {:error, :not_found} = Satellite.fetch_state("NONEXISTENT")

      Satellite.stop("API-TEST-006")
    end
  end

  describe "list/0 and count/0" do
    test "list returns all satellite IDs" do
      {:ok, _} = Satellite.start("API-TEST-007")
      {:ok, _} = Satellite.start("API-TEST-008")

      ids = Satellite.list()
      assert "API-TEST-007" in ids
      assert "API-TEST-008" in ids

      Satellite.stop("API-TEST-007")
      Satellite.stop("API-TEST-008")
    end

    test "count returns the number of satellites" do
      initial = Satellite.count()

      {:ok, _} = Satellite.start("API-TEST-009")
      assert Satellite.count() == initial + 1

      {:ok, _} = Satellite.start("API-TEST-010")
      assert Satellite.count() == initial + 2

      Satellite.stop("API-TEST-009")
      Satellite.stop("API-TEST-010")
    end
  end

  describe "list_states/0" do
    test "returns states for all satellites" do
      {:ok, _} = Satellite.start("API-TEST-011")
      {:ok, _} = Satellite.start("API-TEST-012")

      states = Satellite.list_states()
      ids = Enum.map(states, & &1.id)

      assert "API-TEST-011" in ids
      assert "API-TEST-012" in ids

      Satellite.stop("API-TEST-011")
      Satellite.stop("API-TEST-012")
    end
  end

  describe "update_energy/2" do
    test "updates satellite energy" do
      {:ok, _} = Satellite.start("API-TEST-013")

      assert {:ok, :updated} = Satellite.update_energy("API-TEST-013", -30.0)
      :timer.sleep(10)

      {:ok, state} = Satellite.get_state("API-TEST-013")
      assert state.energy == 70.0

      Satellite.stop("API-TEST-013")
    end

    test "returns error for non-existent satellite" do
      assert {:error, :not_found} = Satellite.update_energy("NONEXISTENT", -10.0)
    end
  end

  describe "update_memory/2" do
    test "updates satellite memory usage" do
      {:ok, _} = Satellite.start("API-TEST-014")

      assert {:ok, :updated} = Satellite.update_memory("API-TEST-014", 256.0)
      :timer.sleep(10)

      {:ok, state} = Satellite.get_state("API-TEST-014")
      assert state.memory_used == 256.0

      Satellite.stop("API-TEST-014")
    end

    test "returns error for non-existent satellite" do
      assert {:error, :not_found} = Satellite.update_memory("NONEXISTENT", 100.0)
    end
  end

  describe "set_mode/2" do
    test "sets satellite mode" do
      {:ok, _} = Satellite.start("API-TEST-015")

      assert {:ok, :updated} = Satellite.set_mode("API-TEST-015", :safe)
      :timer.sleep(10)

      {:ok, state} = Satellite.get_state("API-TEST-015")
      assert state.mode == :safe

      Satellite.stop("API-TEST-015")
    end

    test "returns error for non-existent satellite" do
      assert {:error, :not_found} = Satellite.set_mode("NONEXISTENT", :safe)
    end
  end

  describe "update_position/2" do
    test "updates satellite position" do
      {:ok, _} = Satellite.start("API-TEST-016")

      assert {:ok, :updated} = Satellite.update_position("API-TEST-016", {1000.0, 2000.0, 3000.0})
      :timer.sleep(10)

      {:ok, state} = Satellite.get_state("API-TEST-016")
      assert state.position == {1000.0, 2000.0, 3000.0}

      Satellite.stop("API-TEST-016")
    end

    test "accepts integer coordinates" do
      {:ok, _} = Satellite.start("API-TEST-017")

      assert {:ok, :updated} = Satellite.update_position("API-TEST-017", {1000, 2000, 3000})
      :timer.sleep(10)

      {:ok, state} = Satellite.get_state("API-TEST-017")
      assert state.position == {1000.0, 2000.0, 3000.0}

      Satellite.stop("API-TEST-017")
    end

    test "returns error for non-existent satellite" do
      assert {:error, :not_found} = Satellite.update_position("NONEXISTENT", {0.0, 0.0, 0.0})
    end
  end
end
