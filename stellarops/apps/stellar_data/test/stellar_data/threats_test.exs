defmodule StellarData.ThreatsTest do
  use StellarData.DataCase, async: true

  alias StellarData.Threats
  alias StellarData.Threats.ThreatAssessment
  alias StellarData.SpaceObjects

  @space_object_attrs %{
    norad_id: 40000,
    name: "COSMOS 2543",
    international_designator: "2019-071A",
    object_type: "satellite",
    owner: "RF",
    country_code: "RUS",
    launch_date: ~D[2019-11-25],
    orbital_status: "active",
    tle_line1: "1 40000U 19071A   24023.12345678  .00001234  00000-0  12345-4 0  9998",
    tle_line2: "2 40000  51.6400 123.4567 0001234  12.3456  78.9012 15.48919234123456",
    tle_epoch: ~U[2024-01-23 02:57:46Z],
    apogee_km: 420.5,
    perigee_km: 408.2,
    inclination_deg: 51.64,
    period_min: 92.8,
    rcs_meters: 3.5
  }

  @valid_assessment_attrs %{
    classification: "suspicious",
    capabilities: ["maneuver", "rendezvous"],
    threat_level: "medium",
    intel_summary: "Object demonstrated unusual maneuvering capabilities",
    notes: "Requires continued monitoring",
    assessed_by: "Analyst-001",
    confidence_level: "medium"
  }

  setup do
    {:ok, space_object} = SpaceObjects.create_object(@space_object_attrs)
    {:ok, space_object: space_object}
  end

  # TASK-207: Tests for ThreatAssessment schema
  describe "changeset validations" do
    test "valid attributes create a valid changeset", %{space_object: obj} do
      attrs = Map.put(@valid_assessment_attrs, :space_object_id, obj.id)
      changeset = ThreatAssessment.changeset(%ThreatAssessment{}, attrs)
      assert changeset.valid?
    end

    test "space_object_id is required" do
      changeset = ThreatAssessment.changeset(%ThreatAssessment{}, @valid_assessment_attrs)
      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).space_object_id
    end

    test "classification is required", %{space_object: obj} do
      attrs = @valid_assessment_attrs
      |> Map.delete(:classification)
      |> Map.put(:space_object_id, obj.id)
      
      changeset = ThreatAssessment.changeset(%ThreatAssessment{}, attrs)
      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).classification
    end

    test "classification must be valid enum value", %{space_object: obj} do
      attrs = @valid_assessment_attrs
      |> Map.put(:classification, "invalid")
      |> Map.put(:space_object_id, obj.id)
      
      changeset = ThreatAssessment.changeset(%ThreatAssessment{}, attrs)
      refute changeset.valid?
      assert "is invalid" in errors_on(changeset).classification
    end

    test "accepts all valid classification values", %{space_object: obj} do
      for classification <- ["hostile", "suspicious", "unknown", "friendly"] do
        attrs = @valid_assessment_attrs
        |> Map.put(:classification, classification)
        |> Map.put(:space_object_id, obj.id)
        
        changeset = ThreatAssessment.changeset(%ThreatAssessment{}, attrs)
        assert changeset.valid?, "#{classification} should be valid"
      end
    end

    test "threat_level must be valid enum value", %{space_object: obj} do
      attrs = @valid_assessment_attrs
      |> Map.put(:threat_level, "invalid")
      |> Map.put(:space_object_id, obj.id)
      
      changeset = ThreatAssessment.changeset(%ThreatAssessment{}, attrs)
      refute changeset.valid?
      assert "is invalid" in errors_on(changeset).threat_level
    end

    test "accepts all valid threat levels", %{space_object: obj} do
      for level <- ["critical", "high", "medium", "low", "none"] do
        attrs = @valid_assessment_attrs
        |> Map.put(:threat_level, level)
        |> Map.put(:space_object_id, obj.id)
        
        changeset = ThreatAssessment.changeset(%ThreatAssessment{}, attrs)
        assert changeset.valid?, "#{level} should be valid"
      end
    end

    test "confidence_level must be valid enum value", %{space_object: obj} do
      attrs = @valid_assessment_attrs
      |> Map.put(:confidence_level, "invalid")
      |> Map.put(:space_object_id, obj.id)
      
      changeset = ThreatAssessment.changeset(%ThreatAssessment{}, attrs)
      refute changeset.valid?
      assert "is invalid" in errors_on(changeset).confidence_level
    end

    test "capabilities is an array", %{space_object: obj} do
      attrs = @valid_assessment_attrs
      |> Map.put(:capabilities, ["isr", "maneuver", "signals"])
      |> Map.put(:space_object_id, obj.id)
      
      changeset = ThreatAssessment.changeset(%ThreatAssessment{}, attrs)
      assert changeset.valid?
    end
  end

  # TASK-208: Tests for Threats context
  describe "assess_threat/2" do
    test "creates threat assessment for space object", %{space_object: obj} do
      attrs = Map.put(@valid_assessment_attrs, :space_object_id, obj.id)
      
      assert {:ok, %ThreatAssessment{} = assessment} = Threats.assess_threat(obj, attrs)
      assert assessment.space_object_id == obj.id
      assert assessment.classification == :suspicious
      assert assessment.threat_level == :medium
      assert assessment.confidence_level == :medium
      assert "maneuver" in assessment.capabilities
    end

    test "returns error with invalid attributes", %{space_object: obj} do
      invalid_attrs = %{classification: "invalid"}
      
      assert {:error, %Ecto.Changeset{}} = Threats.assess_threat(obj, invalid_attrs)
    end

    test "sets assessed_at timestamp", %{space_object: obj} do
      attrs = Map.put(@valid_assessment_attrs, :space_object_id, obj.id)
      
      {:ok, assessment} = Threats.assess_threat(obj, attrs)
      assert assessment.assessed_at != nil
      assert DateTime.diff(DateTime.utc_now(), assessment.assessed_at) < 5
    end
  end

  describe "update_assessment/2" do
    setup %{space_object: obj} do
      attrs = Map.put(@valid_assessment_attrs, :space_object_id, obj.id)
      {:ok, assessment} = Threats.assess_threat(obj, attrs)
      {:ok, assessment: assessment}
    end

    test "updates assessment with valid attributes", %{assessment: assessment} do
      update_attrs = %{
        classification: "hostile",
        threat_level: "high",
        intel_summary: "Updated intelligence indicates hostile intent"
      }
      
      assert {:ok, updated} = Threats.update_assessment(assessment, update_attrs)
      assert updated.classification == :hostile
      assert updated.threat_level == :high
      assert updated.intel_summary == "Updated intelligence indicates hostile intent"
    end

    test "returns error with invalid attributes", %{assessment: assessment} do
      assert {:error, %Ecto.Changeset{}} = 
        Threats.update_assessment(assessment, %{classification: "invalid"})
    end
  end

  describe "get_assessment/1" do
    test "returns assessment by id", %{space_object: obj} do
      attrs = Map.put(@valid_assessment_attrs, :space_object_id, obj.id)
      {:ok, assessment} = Threats.assess_threat(obj, attrs)
      
      assert %ThreatAssessment{} = found = Threats.get_assessment(assessment.id)
      assert found.id == assessment.id
    end

    test "returns nil for non-existent id" do
      assert Threats.get_assessment(Ecto.UUID.generate()) == nil
    end
  end

  describe "get_assessment_for_object/1" do
    test "returns latest assessment for object", %{space_object: obj} do
      attrs = Map.put(@valid_assessment_attrs, :space_object_id, obj.id)
      {:ok, assessment} = Threats.assess_threat(obj, attrs)
      
      assert %ThreatAssessment{} = found = Threats.get_assessment_for_object(obj.id)
      assert found.id == assessment.id
    end

    test "returns nil when no assessment exists", %{space_object: obj} do
      # Create another object without assessment
      {:ok, other_obj} = SpaceObjects.create_object(%{@space_object_attrs | norad_id: 40001})
      
      assert Threats.get_assessment_for_object(other_obj.id) == nil
    end
  end

  describe "list_hostile_objects/0" do
    test "returns objects classified as hostile", %{space_object: obj} do
      # Create hostile assessment
      attrs = @valid_assessment_attrs
      |> Map.put(:classification, "hostile")
      |> Map.put(:space_object_id, obj.id)
      
      {:ok, _assessment} = Threats.assess_threat(obj, attrs)
      
      hostile_objects = Threats.list_hostile_objects()
      assert length(hostile_objects) >= 1
      assert Enum.any?(hostile_objects, &(&1.id == obj.id))
    end

    test "does not return non-hostile objects", %{space_object: obj} do
      # Create friendly assessment
      attrs = @valid_assessment_attrs
      |> Map.put(:classification, "friendly")
      |> Map.put(:space_object_id, obj.id)
      
      {:ok, _assessment} = Threats.assess_threat(obj, attrs)
      
      hostile_objects = Threats.list_hostile_objects()
      refute Enum.any?(hostile_objects, &(&1.id == obj.id))
    end
  end

  describe "list_suspicious_objects/0" do
    test "returns objects classified as suspicious", %{space_object: obj} do
      attrs = Map.put(@valid_assessment_attrs, :space_object_id, obj.id)
      {:ok, _assessment} = Threats.assess_threat(obj, attrs)
      
      suspicious_objects = Threats.list_suspicious_objects()
      assert length(suspicious_objects) >= 1
      assert Enum.any?(suspicious_objects, &(&1.id == obj.id))
    end

    test "does not return non-suspicious objects", %{space_object: obj} do
      attrs = @valid_assessment_attrs
      |> Map.put(:classification, "friendly")
      |> Map.put(:space_object_id, obj.id)
      
      {:ok, _assessment} = Threats.assess_threat(obj, attrs)
      
      suspicious_objects = Threats.list_suspicious_objects()
      refute Enum.any?(suspicious_objects, &(&1.id == obj.id))
    end
  end

  describe "list_by_threat_level/1" do
    setup %{space_object: obj} do
      # Create objects with different threat levels
      {:ok, obj2} = SpaceObjects.create_object(%{@space_object_attrs | norad_id: 40001})
      {:ok, obj3} = SpaceObjects.create_object(%{@space_object_attrs | norad_id: 40002})

      {:ok, _} = Threats.assess_threat(obj, %{@valid_assessment_attrs | threat_level: "critical"})
      {:ok, _} = Threats.assess_threat(obj2, %{@valid_assessment_attrs | threat_level: "high"})
      {:ok, _} = Threats.assess_threat(obj3, %{@valid_assessment_attrs | threat_level: "low"})

      :ok
    end

    test "returns objects with specified threat level" do
      critical_objects = Threats.list_by_threat_level("critical")
      assert length(critical_objects) >= 1
      
      high_objects = Threats.list_by_threat_level("high")
      assert length(high_objects) >= 1
    end
  end

  describe "delete_assessment/1" do
    test "deletes assessment", %{space_object: obj} do
      attrs = Map.put(@valid_assessment_attrs, :space_object_id, obj.id)
      {:ok, assessment} = Threats.assess_threat(obj, attrs)
      
      assert {:ok, %ThreatAssessment{}} = Threats.delete_assessment(assessment)
      assert Threats.get_assessment(assessment.id) == nil
    end
  end

  describe "preload associations" do
    test "can preload space_object", %{space_object: obj} do
      attrs = Map.put(@valid_assessment_attrs, :space_object_id, obj.id)
      {:ok, assessment} = Threats.assess_threat(obj, attrs)
      
      loaded = Threats.get_assessment(assessment.id) |> Repo.preload(:space_object)
      assert loaded.space_object.id == obj.id
      assert loaded.space_object.norad_id == obj.norad_id
    end
  end
end
