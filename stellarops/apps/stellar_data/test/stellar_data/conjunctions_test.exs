defmodule StellarData.ConjunctionsTest do
  use StellarData.DataCase, async: true

  alias StellarData.Conjunctions
  alias StellarData.Conjunctions.Conjunction
  alias StellarData.SpaceObjects
  alias StellarData.Satellites

  @satellite_attrs %{
    satellite_id: "SAT-TEST-001",
    name: "Test Satellite",
    mode: :operational,
    energy: 85.0,
    memory_used: 45.0,
    position: %{x_km: 6800.0, y_km: 0.0, z_km: 0.0},
    velocity: %{vx_km_s: 0.0, vy_km_s: 7.5, vz_km_s: 0.0}
  }

  @space_object_attrs %{
    norad_id: 50000,
    name: "Debris Fragment",
    object_type: "debris",
    owner: "Unknown",
    country_code: "UNK",
    orbital_status: "active",
    tle_line1: "1 50000U 22001A   24023.12345678  .00001234  00000-0  12345-4 0  9998",
    tle_line2: "2 50000  51.6400 123.4567 0001234  12.3456  78.9012 15.48919234123456",
    tle_epoch: ~U[2024-01-23 02:57:46Z],
    rcs_meters: 0.5
  }

  @valid_conjunction_attrs %{
    tca: ~U[2024-01-24 12:30:00Z],
    miss_distance_km: 0.85,
    relative_velocity_km_s: 14.2,
    probability_of_collision: 1.5e-4,
    severity: "high",
    status: "active",
    asset_position_at_tca: %{"x" => 6800.0, "y" => 500.0, "z" => 200.0},
    object_position_at_tca: %{"x" => 6801.0, "y" => 500.0, "z" => 200.0}
  }

  setup do
    {:ok, satellite} = Satellites.create_satellite(@satellite_attrs)
    {:ok, space_object} = SpaceObjects.create_object(@space_object_attrs)
    
    {:ok, satellite: satellite, space_object: space_object}
  end

  # TASK-231: Tests for Conjunction schema
  describe "changeset validations" do
    test "valid attributes create a valid changeset", %{satellite: sat, space_object: obj} do
      attrs = @valid_conjunction_attrs
      |> Map.put(:asset_id, sat.id)
      |> Map.put(:object_id, obj.id)
      
      changeset = Conjunction.changeset(%Conjunction{}, attrs)
      assert changeset.valid?
    end

    test "asset_id is required", %{space_object: obj} do
      attrs = Map.put(@valid_conjunction_attrs, :object_id, obj.id)
      changeset = Conjunction.changeset(%Conjunction{}, attrs)
      
      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).asset_id
    end

    test "object_id is required", %{satellite: sat} do
      attrs = Map.put(@valid_conjunction_attrs, :asset_id, sat.id)
      changeset = Conjunction.changeset(%Conjunction{}, attrs)
      
      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).object_id
    end

    test "tca is required", %{satellite: sat, space_object: obj} do
      attrs = @valid_conjunction_attrs
      |> Map.delete(:tca)
      |> Map.put(:asset_id, sat.id)
      |> Map.put(:object_id, obj.id)
      
      changeset = Conjunction.changeset(%Conjunction{}, attrs)
      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).tca
    end

    test "miss_distance_km is required", %{satellite: sat, space_object: obj} do
      attrs = @valid_conjunction_attrs
      |> Map.delete(:miss_distance_km)
      |> Map.put(:asset_id, sat.id)
      |> Map.put(:object_id, obj.id)
      
      changeset = Conjunction.changeset(%Conjunction{}, attrs)
      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).miss_distance_km
    end

    test "miss_distance_km must be non-negative", %{satellite: sat, space_object: obj} do
      attrs = @valid_conjunction_attrs
      |> Map.put(:miss_distance_km, -1.0)
      |> Map.put(:asset_id, sat.id)
      |> Map.put(:object_id, obj.id)
      
      changeset = Conjunction.changeset(%Conjunction{}, attrs)
      refute changeset.valid?
      assert "must be greater than or equal to 0" in errors_on(changeset).miss_distance_km
    end

    test "probability_of_collision must be between 0 and 1", %{satellite: sat, space_object: obj} do
      attrs = @valid_conjunction_attrs
      |> Map.put(:probability_of_collision, 1.5)
      |> Map.put(:asset_id, sat.id)
      |> Map.put(:object_id, obj.id)
      
      changeset = Conjunction.changeset(%Conjunction{}, attrs)
      refute changeset.valid?
      assert "must be less than or equal to 1" in errors_on(changeset).probability_of_collision
    end

    test "severity must be valid enum value", %{satellite: sat, space_object: obj} do
      attrs = @valid_conjunction_attrs
      |> Map.put(:severity, "invalid")
      |> Map.put(:asset_id, sat.id)
      |> Map.put(:object_id, obj.id)
      
      changeset = Conjunction.changeset(%Conjunction{}, attrs)
      refute changeset.valid?
      assert "is invalid" in errors_on(changeset).severity
    end

    test "accepts all valid severity values", %{satellite: sat, space_object: obj} do
      for severity <- ["critical", "high", "medium", "low"] do
        attrs = @valid_conjunction_attrs
        |> Map.put(:severity, severity)
        |> Map.put(:asset_id, sat.id)
        |> Map.put(:object_id, obj.id)
        
        changeset = Conjunction.changeset(%Conjunction{}, attrs)
        assert changeset.valid?, "#{severity} should be valid"
      end
    end

    test "status must be valid enum value", %{satellite: sat, space_object: obj} do
      attrs = @valid_conjunction_attrs
      |> Map.put(:status, "invalid")
      |> Map.put(:asset_id, sat.id)
      |> Map.put(:object_id, obj.id)
      
      changeset = Conjunction.changeset(%Conjunction{}, attrs)
      refute changeset.valid?
      assert "is invalid" in errors_on(changeset).status
    end

    test "accepts all valid status values", %{satellite: sat, space_object: obj} do
      for status <- ["active", "monitoring", "resolved", "expired"] do
        attrs = @valid_conjunction_attrs
        |> Map.put(:status, status)
        |> Map.put(:asset_id, sat.id)
        |> Map.put(:object_id, obj.id)
        
        changeset = Conjunction.changeset(%Conjunction{}, attrs)
        assert changeset.valid?, "#{status} should be valid"
      end
    end

    test "position data is stored as JSON", %{satellite: sat, space_object: obj} do
      attrs = @valid_conjunction_attrs
      |> Map.put(:asset_id, sat.id)
      |> Map.put(:object_id, obj.id)
      
      changeset = Conjunction.changeset(%Conjunction{}, attrs)
      assert changeset.valid?
      assert get_change(changeset, :asset_position_at_tca) == %{"x" => 6800.0, "y" => 500.0, "z" => 200.0}
    end
  end

  # TASK-232: Tests for Conjunctions context
  describe "create_conjunction/1" do
    test "creates conjunction with valid attributes", %{satellite: sat, space_object: obj} do
      attrs = @valid_conjunction_attrs
      |> Map.put(:asset_id, sat.id)
      |> Map.put(:object_id, obj.id)
      
      assert {:ok, %Conjunction{} = conjunction} = Conjunctions.create_conjunction(attrs)
      assert conjunction.asset_id == sat.id
      assert conjunction.object_id == obj.id
      assert conjunction.miss_distance_km == 0.85
      assert conjunction.severity == :high
      assert conjunction.status == :active
    end

    test "returns error with invalid attributes" do
      assert {:error, %Ecto.Changeset{}} = Conjunctions.create_conjunction(%{})
    end
  end

  describe "update_conjunction/2" do
    setup %{satellite: sat, space_object: obj} do
      attrs = @valid_conjunction_attrs
      |> Map.put(:asset_id, sat.id)
      |> Map.put(:object_id, obj.id)
      
      {:ok, conjunction} = Conjunctions.create_conjunction(attrs)
      {:ok, conjunction: conjunction}
    end

    test "updates conjunction with valid attributes", %{conjunction: conj} do
      update_attrs = %{status: "resolved", severity: "medium"}
      
      assert {:ok, updated} = Conjunctions.update_conjunction(conj, update_attrs)
      assert updated.status == :resolved
      assert updated.severity == :medium
    end

    test "returns error with invalid attributes", %{conjunction: conj} do
      assert {:error, %Ecto.Changeset{}} = 
        Conjunctions.update_conjunction(conj, %{severity: "invalid"})
    end
  end

  describe "get_conjunction/1" do
    test "returns conjunction by id", %{satellite: sat, space_object: obj} do
      attrs = @valid_conjunction_attrs
      |> Map.put(:asset_id, sat.id)
      |> Map.put(:object_id, obj.id)
      
      {:ok, conjunction} = Conjunctions.create_conjunction(attrs)
      
      assert %Conjunction{} = found = Conjunctions.get_conjunction(conjunction.id)
      assert found.id == conjunction.id
    end

    test "returns nil for non-existent id" do
      assert Conjunctions.get_conjunction(Ecto.UUID.generate()) == nil
    end
  end

  describe "list_active_conjunctions/0" do
    setup %{satellite: sat, space_object: obj} do
      # Create active conjunction
      active_attrs = @valid_conjunction_attrs
      |> Map.put(:asset_id, sat.id)
      |> Map.put(:object_id, obj.id)
      |> Map.put(:status, "active")
      
      {:ok, active} = Conjunctions.create_conjunction(active_attrs)
      
      # Create resolved conjunction
      resolved_attrs = active_attrs
      |> Map.put(:status, "resolved")
      |> Map.put(:tca, ~U[2024-01-25 12:30:00Z])
      
      {:ok, _resolved} = Conjunctions.create_conjunction(resolved_attrs)
      
      {:ok, active_conjunction: active}
    end

    test "returns only active conjunctions", %{active_conjunction: active} do
      active_conjunctions = Conjunctions.list_active_conjunctions()
      
      assert length(active_conjunctions) >= 1
      assert Enum.all?(active_conjunctions, &(&1.status == :active))
      assert Enum.any?(active_conjunctions, &(&1.id == active.id))
    end
  end

  describe "list_conjunctions_for_asset/1" do
    setup %{satellite: sat, space_object: obj} do
      # Create conjunctions for this asset
      {:ok, conj1} = Conjunctions.create_conjunction(
        Map.merge(@valid_conjunction_attrs, %{asset_id: sat.id, object_id: obj.id})
      )
      
      {:ok, conj2} = Conjunctions.create_conjunction(
        Map.merge(@valid_conjunction_attrs, %{
          asset_id: sat.id, 
          object_id: obj.id,
          tca: ~U[2024-01-25 12:30:00Z]
        })
      )
      
      # Create conjunction for different asset
      {:ok, other_sat} = Satellites.create_satellite(%{@satellite_attrs | satellite_id: "SAT-OTHER"})
      {:ok, _other_conj} = Conjunctions.create_conjunction(
        Map.merge(@valid_conjunction_attrs, %{
          asset_id: other_sat.id, 
          object_id: obj.id,
          tca: ~U[2024-01-26 12:30:00Z]
        })
      )
      
      {:ok, conjunctions: [conj1, conj2]}
    end

    test "returns conjunctions for specific asset", %{satellite: sat, conjunctions: conjs} do
      asset_conjunctions = Conjunctions.list_conjunctions_for_asset(sat.id)
      
      assert length(asset_conjunctions) >= 2
      assert Enum.all?(asset_conjunctions, &(&1.asset_id == sat.id))
      
      conj_ids = Enum.map(conjs, & &1.id)
      assert Enum.all?(conj_ids, &Enum.any?(asset_conjunctions, fn c -> c.id == &1 end))
    end
  end

  describe "list_conjunctions_in_window/2" do
    setup %{satellite: sat, space_object: obj} do
      # Create conjunctions at different times
      {:ok, early} = Conjunctions.create_conjunction(
        Map.merge(@valid_conjunction_attrs, %{
          asset_id: sat.id,
          object_id: obj.id,
          tca: ~U[2024-01-24 06:00:00Z]
        })
      )
      
      {:ok, middle} = Conjunctions.create_conjunction(
        Map.merge(@valid_conjunction_attrs, %{
          asset_id: sat.id,
          object_id: obj.id,
          tca: ~U[2024-01-24 12:00:00Z]
        })
      )
      
      {:ok, late} = Conjunctions.create_conjunction(
        Map.merge(@valid_conjunction_attrs, %{
          asset_id: sat.id,
          object_id: obj.id,
          tca: ~U[2024-01-24 18:00:00Z]
        })
      )
      
      {:ok, early: early, middle: middle, late: late}
    end

    test "returns conjunctions within time window", %{middle: middle} do
      start_time = ~U[2024-01-24 10:00:00Z]
      end_time = ~U[2024-01-24 14:00:00Z]
      
      conjunctions = Conjunctions.list_conjunctions_in_window(start_time, end_time)
      
      assert length(conjunctions) >= 1
      assert Enum.any?(conjunctions, &(&1.id == middle.id))
      assert Enum.all?(conjunctions, fn c ->
        DateTime.compare(c.tca, start_time) != :lt and
        DateTime.compare(c.tca, end_time) != :gt
      end)
    end

    test "excludes conjunctions outside window", %{early: early, late: late} do
      start_time = ~U[2024-01-24 10:00:00Z]
      end_time = ~U[2024-01-24 14:00:00Z]
      
      conjunctions = Conjunctions.list_conjunctions_in_window(start_time, end_time)
      
      refute Enum.any?(conjunctions, &(&1.id == early.id))
      refute Enum.any?(conjunctions, &(&1.id == late.id))
    end
  end

  describe "list_by_severity/1" do
    setup %{satellite: sat, space_object: obj} do
      {:ok, critical} = Conjunctions.create_conjunction(
        Map.merge(@valid_conjunction_attrs, %{
          asset_id: sat.id,
          object_id: obj.id,
          severity: "critical",
          tca: ~U[2024-01-24 06:00:00Z]
        })
      )
      
      {:ok, high} = Conjunctions.create_conjunction(
        Map.merge(@valid_conjunction_attrs, %{
          asset_id: sat.id,
          object_id: obj.id,
          severity: "high",
          tca: ~U[2024-01-24 12:00:00Z]
        })
      )
      
      {:ok, critical: critical, high: high}
    end

    test "returns conjunctions of specific severity", %{critical: critical} do
      critical_conjunctions = Conjunctions.list_by_severity("critical")
      
      assert length(critical_conjunctions) >= 1
      assert Enum.all?(critical_conjunctions, &(&1.severity == :critical))
      assert Enum.any?(critical_conjunctions, &(&1.id == critical.id))
    end
  end

  describe "acknowledge/2" do
    setup %{satellite: sat, space_object: obj} do
      attrs = @valid_conjunction_attrs
      |> Map.put(:asset_id, sat.id)
      |> Map.put(:object_id, obj.id)
      
      {:ok, conjunction} = Conjunctions.create_conjunction(attrs)
      {:ok, conjunction: conjunction}
    end

    test "updates conjunction status to monitoring", %{conjunction: conj} do
      assert {:ok, updated} = Conjunctions.acknowledge(conj, "Operator-001")
      assert updated.status == :monitoring
    end
  end

  describe "resolve/1" do
    setup %{satellite: sat, space_object: obj} do
      attrs = @valid_conjunction_attrs
      |> Map.put(:asset_id, sat.id)
      |> Map.put(:object_id, obj.id)
      
      {:ok, conjunction} = Conjunctions.create_conjunction(attrs)
      {:ok, conjunction: conjunction}
    end

    test "updates conjunction status to resolved", %{conjunction: conj} do
      assert {:ok, updated} = Conjunctions.resolve(conj)
      assert updated.status == :resolved
    end
  end

  describe "mark_expired/1" do
    setup %{satellite: sat, space_object: obj} do
      # Create conjunction with past TCA
      past_tca = DateTime.add(DateTime.utc_now(), -3600, :second)
      attrs = @valid_conjunction_attrs
      |> Map.put(:asset_id, sat.id)
      |> Map.put(:object_id, obj.id)
      |> Map.put(:tca, past_tca)
      
      {:ok, conjunction} = Conjunctions.create_conjunction(attrs)
      {:ok, conjunction: conjunction}
    end

    test "marks conjunction as expired", %{conjunction: conj} do
      assert {:ok, updated} = Conjunctions.mark_expired(conj)
      assert updated.status == :expired
    end
  end

  describe "delete_conjunction/1" do
    test "deletes conjunction", %{satellite: sat, space_object: obj} do
      attrs = @valid_conjunction_attrs
      |> Map.put(:asset_id, sat.id)
      |> Map.put(:object_id, obj.id)
      
      {:ok, conjunction} = Conjunctions.create_conjunction(attrs)
      
      assert {:ok, %Conjunction{}} = Conjunctions.delete_conjunction(conjunction)
      assert Conjunctions.get_conjunction(conjunction.id) == nil
    end
  end

  describe "preload associations" do
    test "can preload asset and object", %{satellite: sat, space_object: obj} do
      attrs = @valid_conjunction_attrs
      |> Map.put(:asset_id, sat.id)
      |> Map.put(:object_id, obj.id)
      
      {:ok, conjunction} = Conjunctions.create_conjunction(attrs)
      
      loaded = Conjunctions.get_conjunction(conjunction.id) 
      |> Repo.preload([:asset, :object])
      
      assert loaded.asset.id == sat.id
      assert loaded.object.id == obj.id
    end
  end
end
