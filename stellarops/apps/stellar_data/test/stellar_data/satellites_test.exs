defmodule StellarData.SatellitesTest do
  use StellarData.DataCase, async: true

  alias StellarData.Satellites

  describe "list_satellites/0" do
    test "returns empty list when no satellites" do
      assert Satellites.list_satellites() == []
    end

    test "returns all satellites" do
      {:ok, sat1} = Satellites.create_satellite(%{id: "sat-1", name: "Sat 1"})
      {:ok, sat2} = Satellites.create_satellite(%{id: "sat-2", name: "Sat 2"})

      satellites = Satellites.list_satellites()
      assert length(satellites) == 2
      assert Enum.any?(satellites, &(&1.id == sat1.id))
      assert Enum.any?(satellites, &(&1.id == sat2.id))
    end
  end

  describe "list_active_satellites/0" do
    test "returns only active satellites" do
      {:ok, _active} = Satellites.create_satellite(%{id: "active-sat", active: true})
      {:ok, _inactive} = Satellites.create_satellite(%{id: "inactive-sat", active: false})

      active_satellites = Satellites.list_active_satellites()
      assert length(active_satellites) == 1
      assert hd(active_satellites).id == "active-sat"
    end
  end

  describe "get_satellite/1" do
    test "returns satellite with given id" do
      {:ok, satellite} = Satellites.create_satellite(%{id: "sat-get", name: "Get Test"})

      assert found = Satellites.get_satellite(satellite.id)
      assert found.id == satellite.id
    end

    test "returns nil when satellite does not exist" do
      assert Satellites.get_satellite("nonexistent") == nil
    end
  end

  describe "get_satellite!/1" do
    test "returns satellite with given id" do
      {:ok, satellite} = Satellites.create_satellite(%{id: "sat-get!", name: "Get! Test"})

      assert found = Satellites.get_satellite!(satellite.id)
      assert found.id == satellite.id
    end

    test "raises when satellite does not exist" do
      assert_raise Ecto.NoResultsError, fn ->
        Satellites.get_satellite!("nonexistent")
      end
    end
  end

  describe "create_satellite/1" do
    test "creates satellite with valid attrs" do
      attrs = %{
        id: "new-sat",
        name: "New Satellite",
        mode: :safe,
        energy: 75.0
      }

      assert {:ok, satellite} = Satellites.create_satellite(attrs)
      assert satellite.id == "new-sat"
      assert satellite.name == "New Satellite"
      assert satellite.mode == :safe
      assert satellite.energy == 75.0
    end

    test "returns error with invalid attrs" do
      assert {:error, changeset} = Satellites.create_satellite(%{})
      refute changeset.valid?
    end
  end

  describe "update_satellite/2" do
    test "updates satellite with valid attrs" do
      {:ok, satellite} = Satellites.create_satellite(%{id: "update-sat", name: "Original"})

      assert {:ok, updated} = Satellites.update_satellite(satellite, %{name: "Updated"})
      assert updated.name == "Updated"
    end

    test "returns error with invalid attrs" do
      {:ok, satellite} = Satellites.create_satellite(%{id: "update-fail", name: "Original"})

      assert {:error, changeset} = Satellites.update_satellite(satellite, %{energy: -10.0})
      refute changeset.valid?
    end
  end

  describe "update_satellite_state/2" do
    test "updates state fields" do
      {:ok, satellite} = Satellites.create_satellite(%{id: "state-sat"})

      assert {:ok, updated} = Satellites.update_satellite_state(satellite, %{
        mode: :survival,
        energy: 50.0,
        memory_used: 1024.0
      })

      assert updated.mode == :survival
      assert updated.energy == 50.0
      assert updated.memory_used == 1024.0
    end
  end

  describe "update_satellite_state_by_id/2" do
    test "updates satellite by id" do
      {:ok, satellite} = Satellites.create_satellite(%{id: "state-by-id-sat"})

      assert {:ok, updated} = Satellites.update_satellite_state_by_id(satellite.id, %{
        mode: :safe
      })

      assert updated.mode == :safe
    end

    test "returns error for nonexistent satellite" do
      assert {:error, :not_found} = Satellites.update_satellite_state_by_id("nonexistent", %{})
    end
  end

  describe "delete_satellite/1" do
    test "deletes the satellite" do
      {:ok, satellite} = Satellites.create_satellite(%{id: "delete-sat", name: "Delete Me"})

      assert {:ok, deleted} = Satellites.delete_satellite(satellite)
      assert deleted.id == satellite.id
      assert Satellites.get_satellite(satellite.id) == nil
    end
  end

  describe "upsert_satellite/1" do
    test "creates new satellite" do
      attrs = %{id: "upsert-new", name: "New"}

      assert {:ok, satellite} = Satellites.upsert_satellite(attrs)
      assert satellite.id == "upsert-new"
    end

    test "updates existing satellite" do
      {:ok, _} = Satellites.create_satellite(%{id: "upsert-existing", name: "Original"})

      assert {:ok, updated} = Satellites.upsert_satellite(%{id: "upsert-existing", name: "Updated"})
      assert updated.name == "Updated"
    end
  end

  describe "sync_satellite_state/2" do
    test "creates new satellite from state map" do
      state_map = %{
        mode: :safe,
        energy: 85.5,
        memory_used: 1024.0,
        position: {100.0, 200.0, 300.0}
      }

      assert {:ok, satellite} = Satellites.sync_satellite_state("sync-new-sat", state_map)
      assert satellite.id == "sync-new-sat"
      assert satellite.mode == :safe
      assert satellite.energy == 85.5
      assert satellite.memory_used == 1024.0
      assert satellite.position_x == 100.0
      assert satellite.position_y == 200.0
      assert satellite.position_z == 300.0
    end

    test "updates existing satellite from state map" do
      {:ok, _} = Satellites.create_satellite(%{id: "sync-existing-sat", name: "Existing"})

      state_map = %{
        mode: :survival,
        energy: 25.0,
        memory_used: 2048.0,
        position: {50.0, 60.0, 70.0}
      }

      assert {:ok, updated} = Satellites.sync_satellite_state("sync-existing-sat", state_map)
      assert updated.mode == :survival
      assert updated.energy == 25.0
    end
  end
end
