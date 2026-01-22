defmodule StellarData.COAsTest do
  @moduledoc """
  Tests for the COAs context module.
  """

  use StellarData.DataCase, async: true

  alias StellarData.COAs
  alias StellarData.COAs.COA

  # ============================================================================
  # Test Fixtures
  # ============================================================================

  defp setup_conjunction do
    # Create satellite
    {:ok, satellite} = StellarData.Satellites.create_satellite(%{
      satellite_id: "SAT-COA-#{:rand.uniform(10000)}",
      name: "Test Satellite",
      status: :active
    })

    # Create space object
    {:ok, object} = StellarData.SpaceObjects.create_object(%{
      norad_id: "#{:rand.uniform(99999)}",
      name: "Debris #{:rand.uniform(1000)}",
      object_type: :debris,
      epoch: DateTime.utc_now(),
      inclination: 45.0,
      raan: 100.0,
      eccentricity: 0.001,
      argument_of_perigee: 90.0,
      mean_anomaly: 180.0,
      mean_motion: 15.5
    })

    # Create conjunction
    {:ok, conjunction} = StellarData.Conjunctions.create_conjunction(%{
      asset_id: satellite.id,
      object_id: object.id,
      tca: DateTime.add(DateTime.utc_now(), 86400, :second),
      miss_distance_km: 0.5,
      probability: 0.001,
      relative_velocity_km_s: 10.0,
      status: :detected
    })

    {satellite, object, conjunction}
  end

  defp valid_coa_attrs(conjunction_id) do
    %{
      conjunction_id: conjunction_id,
      type: :retrograde_burn,
      name: "Retrograde Burn Option",
      objective: "Increase miss distance",
      description: "Lower orbit to increase miss distance",
      delta_v_magnitude: 1.5,
      delta_v_direction: %{"x" => -1.0, "y" => 0.0, "z" => 0.0},
      burn_start_time: DateTime.add(DateTime.utc_now(), 3600, :second),
      burn_duration_seconds: 120.0,
      estimated_fuel_kg: 2.5,
      predicted_miss_distance_km: 5.0,
      risk_score: 25.0,
      pre_burn_orbit: %{"a" => 6771.0, "e" => 0.001, "i" => 45.0},
      post_burn_orbit: %{"a" => 6750.0, "e" => 0.0015, "i" => 45.0}
    }
  end

  # ============================================================================
  # TASK-312: COA CRUD Tests
  # ============================================================================

  describe "create_coa/1" do
    test "creates a COA with valid attributes" do
      {_satellite, _object, conjunction} = setup_conjunction()
      attrs = valid_coa_attrs(conjunction.id)

      assert {:ok, %COA{} = coa} = COAs.create_coa(attrs)
      assert coa.conjunction_id == conjunction.id
      assert coa.type == :retrograde_burn
      assert coa.name == "Retrograde Burn Option"
      assert coa.delta_v_magnitude == 1.5
      assert coa.status == :proposed
      assert coa.risk_score == 25.0
    end

    test "fails with missing required fields" do
      assert {:error, changeset} = COAs.create_coa(%{})
      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).conjunction_id
      assert "can't be blank" in errors_on(changeset).type
      assert "can't be blank" in errors_on(changeset).name
    end

    test "fails with invalid COA type" do
      {_satellite, _object, conjunction} = setup_conjunction()
      attrs = valid_coa_attrs(conjunction.id) |> Map.put(:type, :invalid_type)

      assert {:error, changeset} = COAs.create_coa(attrs)
      refute changeset.valid?
    end

    test "fails with negative delta_v" do
      {_satellite, _object, conjunction} = setup_conjunction()
      attrs = valid_coa_attrs(conjunction.id) |> Map.put(:delta_v_magnitude, -1.0)

      assert {:error, changeset} = COAs.create_coa(attrs)
      assert "must be greater than or equal to 0" in errors_on(changeset).delta_v_magnitude
    end

    test "fails with risk_score out of range" do
      {_satellite, _object, conjunction} = setup_conjunction()
      attrs = valid_coa_attrs(conjunction.id) |> Map.put(:risk_score, 150.0)

      assert {:error, changeset} = COAs.create_coa(attrs)
      assert "must be less than or equal to 100" in errors_on(changeset).risk_score
    end
  end

  describe "get_coa/1" do
    test "returns COA when exists" do
      {_satellite, _object, conjunction} = setup_conjunction()
      {:ok, coa} = COAs.create_coa(valid_coa_attrs(conjunction.id))

      assert fetched = COAs.get_coa(coa.id)
      assert fetched.id == coa.id
    end

    test "returns nil when not found" do
      assert COAs.get_coa(Ecto.UUID.generate()) == nil
    end

    test "returns nil for invalid ID" do
      assert COAs.get_coa("invalid") == nil
    end
  end

  describe "update_coa/2" do
    test "updates COA with valid attributes" do
      {_satellite, _object, conjunction} = setup_conjunction()
      {:ok, coa} = COAs.create_coa(valid_coa_attrs(conjunction.id))

      assert {:ok, updated} = COAs.update_coa(coa, %{risk_score: 30.0})
      assert updated.risk_score == 30.0
    end
  end

  describe "list_coas_for_conjunction/1" do
    test "returns COAs ordered by risk score" do
      {_satellite, _object, conjunction} = setup_conjunction()

      {:ok, _coa1} = COAs.create_coa(valid_coa_attrs(conjunction.id) |> Map.put(:risk_score, 50.0))
      {:ok, _coa2} = COAs.create_coa(valid_coa_attrs(conjunction.id) |> Map.merge(%{risk_score: 20.0, type: :inclination_change, name: "Inc Change"}))
      {:ok, _coa3} = COAs.create_coa(valid_coa_attrs(conjunction.id) |> Map.merge(%{risk_score: 35.0, type: :phasing, name: "Phasing"}))

      coas = COAs.list_coas_for_conjunction(conjunction.id)

      assert length(coas) == 3
      assert Enum.at(coas, 0).risk_score == 20.0
      assert Enum.at(coas, 1).risk_score == 35.0
      assert Enum.at(coas, 2).risk_score == 50.0
    end

    test "returns empty list when no COAs" do
      assert COAs.list_coas_for_conjunction(Ecto.UUID.generate()) == []
    end
  end

  # ============================================================================
  # TASK-313: COA Status Transition Tests
  # ============================================================================

  describe "select_coa/2" do
    test "selects COA and rejects others" do
      {_satellite, _object, conjunction} = setup_conjunction()

      {:ok, coa1} = COAs.create_coa(valid_coa_attrs(conjunction.id))
      {:ok, coa2} = COAs.create_coa(valid_coa_attrs(conjunction.id) |> Map.merge(%{type: :inclination_change, name: "Inc Change"}))

      assert {:ok, selected} = COAs.select_coa(coa1, "test_operator")
      assert selected.status == :selected
      assert selected.selected_by == "test_operator"
      assert selected.selected_at != nil

      # Verify other COA was rejected
      other = COAs.get_coa(coa2.id)
      assert other.status == :rejected
    end
  end

  describe "execute_coa/1" do
    test "transitions COA to executing status" do
      {_satellite, _object, conjunction} = setup_conjunction()
      {:ok, coa} = COAs.create_coa(valid_coa_attrs(conjunction.id))
      {:ok, selected} = COAs.select_coa(coa, "operator")

      assert {:ok, executing} = COAs.execute_coa(selected)
      assert executing.status == :executing
      assert executing.executed_at != nil
    end
  end

  describe "complete_coa/1" do
    test "transitions COA to completed status" do
      {_satellite, _object, conjunction} = setup_conjunction()
      {:ok, coa} = COAs.create_coa(valid_coa_attrs(conjunction.id))
      {:ok, selected} = COAs.select_coa(coa, "operator")
      {:ok, executing} = COAs.execute_coa(selected)

      assert {:ok, completed} = COAs.complete_coa(executing)
      assert completed.status == :completed
      assert completed.completed_at != nil
    end
  end

  describe "fail_coa/2" do
    test "transitions COA to failed status with reason" do
      {_satellite, _object, conjunction} = setup_conjunction()
      {:ok, coa} = COAs.create_coa(valid_coa_attrs(conjunction.id))
      {:ok, selected} = COAs.select_coa(coa, "operator")
      {:ok, executing} = COAs.execute_coa(selected)

      assert {:ok, failed} = COAs.fail_coa(executing, "Thruster malfunction")
      assert failed.status == :failed
      assert failed.failure_reason == "Thruster malfunction"
    end
  end

  describe "reject_coa/1" do
    test "transitions COA to rejected status" do
      {_satellite, _object, conjunction} = setup_conjunction()
      {:ok, coa} = COAs.create_coa(valid_coa_attrs(conjunction.id))

      assert {:ok, rejected} = COAs.reject_coa(coa)
      assert rejected.status == :rejected
    end
  end

  describe "delete_coa/1" do
    test "deletes proposed COA" do
      {_satellite, _object, conjunction} = setup_conjunction()
      {:ok, coa} = COAs.create_coa(valid_coa_attrs(conjunction.id))

      assert {:ok, _} = COAs.delete_coa(coa)
      assert COAs.get_coa(coa.id) == nil
    end

    test "cannot delete selected COA" do
      {_satellite, _object, conjunction} = setup_conjunction()
      {:ok, coa} = COAs.create_coa(valid_coa_attrs(conjunction.id))
      {:ok, selected} = COAs.select_coa(coa, "operator")

      assert {:error, :cannot_delete_active_coa} = COAs.delete_coa(selected)
    end
  end

  describe "get_best_coa_for_conjunction/1" do
    test "returns COA with lowest risk score" do
      {_satellite, _object, conjunction} = setup_conjunction()

      {:ok, _coa1} = COAs.create_coa(valid_coa_attrs(conjunction.id) |> Map.put(:risk_score, 50.0))
      {:ok, best} = COAs.create_coa(valid_coa_attrs(conjunction.id) |> Map.merge(%{risk_score: 15.0, type: :phasing, name: "Best"}))

      result = COAs.get_best_coa_for_conjunction(conjunction.id)
      assert result.id == best.id
    end
  end

  # ============================================================================
  # Helper Functions
  # ============================================================================

  defp errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
  end
end
