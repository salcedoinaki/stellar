defmodule StellarCore.Satellite.RegistryTest do
  use ExUnit.Case, async: false

  alias StellarCore.Satellite.{Registry, Supervisor}

  setup do
    # Clean up any satellites from previous tests
    for id <- Registry.list_ids() do
      Supervisor.stop_satellite(id)
    end

    :ok
  end

  describe "via_tuple/1" do
    test "returns a via tuple for the registry" do
      result = Registry.via_tuple("SAT-001")
      # The via tuple format is {:via, Registry, {registry_name, key}}
      # We need to use Elixir.Registry since Registry is aliased in this file
      assert {:via, Elixir.Registry, {StellarCore.Satellite.Registry, "SAT-001"}} == result
    end
  end

  describe "lookup/1" do
    test "returns {:ok, pid} for registered process" do
      {:ok, pid} = Supervisor.start_satellite("TEST-REG-001")

      assert {:ok, ^pid} = Registry.lookup("TEST-REG-001")

      Supervisor.stop_satellite("TEST-REG-001")
    end

    test "returns :error for non-existent process" do
      assert :error = Registry.lookup("NONEXISTENT")
    end
  end

  describe "list_ids/0" do
    test "returns all registered satellite IDs" do
      {:ok, _} = Supervisor.start_satellite("TEST-REG-002")
      {:ok, _} = Supervisor.start_satellite("TEST-REG-003")

      ids = Registry.list_ids()
      assert "TEST-REG-002" in ids
      assert "TEST-REG-003" in ids

      Supervisor.stop_satellite("TEST-REG-002")
      Supervisor.stop_satellite("TEST-REG-003")
    end
  end

  describe "count/0" do
    test "returns the count of registered processes" do
      initial_count = Registry.count()

      {:ok, _} = Supervisor.start_satellite("TEST-REG-004")
      assert Registry.count() == initial_count + 1

      {:ok, _} = Supervisor.start_satellite("TEST-REG-005")
      assert Registry.count() == initial_count + 2

      Supervisor.stop_satellite("TEST-REG-004")
      Supervisor.stop_satellite("TEST-REG-005")
    end
  end
end
