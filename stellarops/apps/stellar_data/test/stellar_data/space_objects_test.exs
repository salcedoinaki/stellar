defmodule StellarData.SpaceObjectsTest do
  use StellarData.DataCase, async: true

  alias StellarData.SpaceObjects
  alias StellarData.SpaceObjects.SpaceObject

  @valid_attrs %{
    norad_id: 25544,
    name: "ISS (ZARYA)",
    international_designator: "1998-067A",
    object_type: "satellite",
    owner: "ISS",
    country_code: "ISS",
    launch_date: ~D[1998-11-20],
    orbital_status: "active",
    tle_line1: "1 25544U 98067A   24023.12345678  .00001234  00000-0  12345-4 0  9998",
    tle_line2: "2 25544  51.6400 123.4567 0001234  12.3456  78.9012 15.48919234123456",
    tle_epoch: ~U[2024-01-23 02:57:46Z],
    apogee_km: 420.5,
    perigee_km: 408.2,
    inclination_deg: 51.64,
    period_min: 92.8,
    rcs_meters: 10.5
  }

  @invalid_attrs %{
    norad_id: nil,
    name: nil,
    tle_line1: "invalid",
    tle_line2: "invalid"
  }

  # TASK-190: Tests for SpaceObject changeset validations
  describe "changeset validations" do
    test "valid attributes create a valid changeset" do
      changeset = SpaceObject.changeset(%SpaceObject{}, @valid_attrs)
      assert changeset.valid?
    end

    test "norad_id is required" do
      attrs = Map.delete(@valid_attrs, :norad_id)
      changeset = SpaceObject.changeset(%SpaceObject{}, attrs)
      
      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).norad_id
    end

    test "name is required" do
      attrs = Map.delete(@valid_attrs, :name)
      changeset = SpaceObject.changeset(%SpaceObject{}, attrs)
      
      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).name
    end

    test "tle_line1 must be exactly 69 characters" do
      attrs = Map.put(@valid_attrs, :tle_line1, "too short")
      changeset = SpaceObject.changeset(%SpaceObject{}, attrs)
      
      refute changeset.valid?
      assert "should be 69 character(s)" in errors_on(changeset).tle_line1
    end

    test "tle_line2 must be exactly 69 characters" do
      attrs = Map.put(@valid_attrs, :tle_line2, "too short")
      changeset = SpaceObject.changeset(%SpaceObject{}, attrs)
      
      refute changeset.valid?
      assert "should be 69 character(s)" in errors_on(changeset).tle_line2
    end

    test "object_type must be valid enum value" do
      attrs = Map.put(@valid_attrs, :object_type, "invalid_type")
      changeset = SpaceObject.changeset(%SpaceObject{}, attrs)
      
      refute changeset.valid?
      assert "is invalid" in errors_on(changeset).object_type
    end

    test "orbital_status must be valid enum value" do
      attrs = Map.put(@valid_attrs, :orbital_status, "invalid_status")
      changeset = SpaceObject.changeset(%SpaceObject{}, attrs)
      
      refute changeset.valid?
      assert "is invalid" in errors_on(changeset).orbital_status
    end

    test "norad_id must be positive" do
      attrs = Map.put(@valid_attrs, :norad_id, -1)
      changeset = SpaceObject.changeset(%SpaceObject{}, attrs)
      
      refute changeset.valid?
      assert "must be greater than 0" in errors_on(changeset).norad_id
    end

    test "rcs_meters must be non-negative" do
      attrs = Map.put(@valid_attrs, :rcs_meters, -1.0)
      changeset = SpaceObject.changeset(%SpaceObject{}, attrs)
      
      refute changeset.valid?
      assert "must be greater than or equal to 0" in errors_on(changeset).rcs_meters
    end

    test "accepts all valid object types" do
      for type <- ["satellite", "debris", "rocket_body", "unknown"] do
        attrs = Map.put(@valid_attrs, :object_type, type)
        changeset = SpaceObject.changeset(%SpaceObject{}, attrs)
        assert changeset.valid?, "#{type} should be valid"
      end
    end

    test "accepts all valid orbital statuses" do
      for status <- ["active", "decayed", "retired"] do
        attrs = Map.put(@valid_attrs, :orbital_status, status)
        changeset = SpaceObject.changeset(%SpaceObject{}, attrs)
        assert changeset.valid?, "#{status} should be valid"
      end
    end
  end

  # TASK-191: Tests for SpaceObjects context functions
  describe "create_object/1" do
    test "creates space object with valid attributes" do
      assert {:ok, %SpaceObject{} = object} = SpaceObjects.create_object(@valid_attrs)
      assert object.norad_id == 25544
      assert object.name == "ISS (ZARYA)"
      assert object.object_type == :satellite
      assert object.orbital_status == :active
    end

    test "returns error with invalid attributes" do
      assert {:error, %Ecto.Changeset{}} = SpaceObjects.create_object(@invalid_attrs)
    end

    test "enforces unique norad_id constraint" do
      {:ok, _object} = SpaceObjects.create_object(@valid_attrs)
      
      assert {:error, %Ecto.Changeset{} = changeset} = 
        SpaceObjects.create_object(@valid_attrs)
      
      assert "has already been taken" in errors_on(changeset).norad_id
    end
  end

  describe "update_object/2" do
    test "updates object with valid attributes" do
      {:ok, object} = SpaceObjects.create_object(@valid_attrs)
      
      update_attrs = %{name: "ISS (Updated)", apogee_km: 425.0}
      assert {:ok, %SpaceObject{} = updated} = SpaceObjects.update_object(object, update_attrs)
      assert updated.name == "ISS (Updated)"
      assert updated.apogee_km == 425.0
    end

    test "returns error with invalid attributes" do
      {:ok, object} = SpaceObjects.create_object(@valid_attrs)
      
      assert {:error, %Ecto.Changeset{}} = 
        SpaceObjects.update_object(object, %{norad_id: nil})
    end
  end

  describe "get_object/1" do
    test "returns object by id" do
      {:ok, object} = SpaceObjects.create_object(@valid_attrs)
      
      assert %SpaceObject{} = found = SpaceObjects.get_object(object.id)
      assert found.id == object.id
      assert found.norad_id == object.norad_id
    end

    test "returns nil for non-existent id" do
      assert SpaceObjects.get_object(Ecto.UUID.generate()) == nil
    end
  end

  describe "get_object_by_norad_id/1" do
    test "returns object by NORAD ID" do
      {:ok, object} = SpaceObjects.create_object(@valid_attrs)
      
      assert %SpaceObject{} = found = SpaceObjects.get_object_by_norad_id(25544)
      assert found.norad_id == 25544
      assert found.id == object.id
    end

    test "returns nil for non-existent NORAD ID" do
      assert SpaceObjects.get_object_by_norad_id(99999) == nil
    end
  end

  describe "list_objects/1" do
    setup do
      # Create multiple test objects
      {:ok, sat1} = SpaceObjects.create_object(@valid_attrs)
      
      {:ok, sat2} = SpaceObjects.create_object(%{
        @valid_attrs | 
        norad_id: 25545,
        name: "Test Satellite 2",
        object_type: "debris"
      })

      {:ok, sat3} = SpaceObjects.create_object(%{
        @valid_attrs | 
        norad_id: 25546,
        name: "Test Satellite 3",
        orbital_status: "decayed"
      })

      {:ok, satellites: [sat1, sat2, sat3]}
    end

    test "lists all objects without filters", %{satellites: _sats} do
      objects = SpaceObjects.list_objects()
      assert length(objects) >= 3
    end

    test "filters by object_type", %{satellites: _sats} do
      objects = SpaceObjects.list_objects(%{object_type: "satellite"})
      assert length(objects) >= 2
      assert Enum.all?(objects, &(&1.object_type == :satellite))
    end

    test "filters by orbital_status", %{satellites: _sats} do
      objects = SpaceObjects.list_objects(%{orbital_status: "decayed"})
      assert length(objects) >= 1
      assert Enum.all?(objects, &(&1.orbital_status == :decayed))
    end

    test "filters by country_code", %{satellites: _sats} do
      objects = SpaceObjects.list_objects(%{country_code: "ISS"})
      assert length(objects) >= 3
    end
  end

  describe "search_objects/1" do
    setup do
      {:ok, _sat1} = SpaceObjects.create_object(@valid_attrs)
      
      {:ok, _sat2} = SpaceObjects.create_object(%{
        @valid_attrs | 
        norad_id: 25545,
        name: "COSMOS 2544"
      })

      :ok
    end

    test "searches by name substring" do
      results = SpaceObjects.search_objects("ISS")
      assert length(results) >= 1
      assert Enum.any?(results, &String.contains?(&1.name, "ISS"))
    end

    test "searches by NORAD ID as string" do
      results = SpaceObjects.search_objects("25544")
      assert length(results) >= 1
      assert Enum.any?(results, &(&1.norad_id == 25544))
    end

    test "search is case-insensitive" do
      results = SpaceObjects.search_objects("iss")
      assert length(results) >= 1
    end

    test "returns empty list for no matches" do
      results = SpaceObjects.search_objects("NONEXISTENT")
      assert results == []
    end
  end

  describe "update_tle/3" do
    test "updates TLE data" do
      {:ok, object} = SpaceObjects.create_object(@valid_attrs)
      
      new_tle1 = "1 25544U 98067A   24024.12345678  .00001234  00000-0  12345-4 0  9999"
      new_tle2 = "2 25544  51.6401 123.4567 0001234  12.3456  78.9012 15.48919235123457"
      new_epoch = ~U[2024-01-24 02:57:46Z]

      assert {:ok, updated} = SpaceObjects.update_tle(object, new_tle1, new_tle2, new_epoch)
      assert updated.tle_line1 == new_tle1
      assert updated.tle_line2 == new_tle2
      assert updated.tle_epoch == new_epoch
    end

    test "validates TLE line lengths" do
      {:ok, object} = SpaceObjects.create_object(@valid_attrs)
      
      assert {:error, %Ecto.Changeset{}} = 
        SpaceObjects.update_tle(object, "invalid", "invalid", DateTime.utc_now())
    end
  end

  describe "delete_object/1" do
    test "deletes object" do
      {:ok, object} = SpaceObjects.create_object(@valid_attrs)
      
      assert {:ok, %SpaceObject{}} = SpaceObjects.delete_object(object)
      assert SpaceObjects.get_object(object.id) == nil
    end
  end

  describe "get_active_satellites/0" do
    setup do
      {:ok, _sat1} = SpaceObjects.create_object(@valid_attrs)
      
      {:ok, _debris} = SpaceObjects.create_object(%{
        @valid_attrs | 
        norad_id: 25545,
        object_type: "debris"
      })

      {:ok, _decayed} = SpaceObjects.create_object(%{
        @valid_attrs | 
        norad_id: 25546,
        orbital_status: "decayed"
      })

      :ok
    end

    test "returns only active satellites" do
      satellites = SpaceObjects.get_active_satellites()
      assert length(satellites) >= 1
      assert Enum.all?(satellites, &(&1.object_type == :satellite))
      assert Enum.all?(satellites, &(&1.orbital_status == :active))
    end
  end
end
