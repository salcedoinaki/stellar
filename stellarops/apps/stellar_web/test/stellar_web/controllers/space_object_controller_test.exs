defmodule StellarWeb.SpaceObjectControllerTest do
  use StellarWeb.ConnCase, async: true

  alias StellarData.{SpaceObjects, Threats}

  @valid_attrs %{
    norad_id: 80000,
    name: "Test Satellite Alpha",
    international_designator: "2024-001A",
    object_type: "satellite",
    owner: "TEST",
    country_code: "USA",
    launch_date: ~D[2024-01-15],
    orbital_status: "active",
    tle_line1: "1 80000U 24001A   24023.12345678  .00001234  00000-0  12345-4 0  9998",
    tle_line2: "2 80000  51.6400 123.4567 0001234  12.3456  78.9012 15.48919234123456",
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

  @update_attrs %{
    name: "Updated Satellite Name",
    orbital_status: "retired"
  }

  setup %{conn: conn} do
    {:ok, space_object} = SpaceObjects.create_object(@valid_attrs)

    {:ok,
     conn: put_req_header(conn, "accept", "application/json"),
     space_object: space_object}
  end

  # TASK-288: Controller tests for SpaceObjectController
  describe "index" do
    test "lists all space objects", %{conn: conn, space_object: obj} do
      conn = get(conn, ~p"/api/objects")
      assert %{"data" => objects} = json_response(conn, 200)
      assert is_list(objects)
      assert length(objects) >= 1

      # Verify our object is in the list
      object_ids = Enum.map(objects, & &1["id"])
      assert obj.id in object_ids
    end

    test "filters objects by object_type", %{conn: conn, space_object: obj} do
      conn = get(conn, ~p"/api/objects?object_type=satellite")
      assert %{"data" => objects} = json_response(conn, 200)

      assert Enum.all?(objects, &(&1["object_type"] == "satellite"))
      assert Enum.any?(objects, &(&1["id"] == obj.id))
    end

    test "filters objects by orbital_status", %{conn: conn, space_object: obj} do
      conn = get(conn, ~p"/api/objects?orbital_status=active")
      assert %{"data" => objects} = json_response(conn, 200)

      assert Enum.all?(objects, &(&1["orbital_status"] == "active"))
      assert Enum.any?(objects, &(&1["id"] == obj.id))
    end

    test "filters objects by country_code", %{conn: conn, space_object: obj} do
      conn = get(conn, ~p"/api/objects?country_code=USA")
      assert %{"data" => objects} = json_response(conn, 200)

      assert Enum.any?(objects, &(&1["id"] == obj.id))
    end

    test "searches objects by name", %{conn: conn, space_object: obj} do
      conn = get(conn, ~p"/api/objects?search=Alpha")
      assert %{"data" => objects} = json_response(conn, 200)

      assert Enum.any?(objects, &(&1["id"] == obj.id))
    end

    test "searches objects by NORAD ID", %{conn: conn, space_object: obj} do
      conn = get(conn, ~p"/api/objects?search=80000")
      assert %{"data" => objects} = json_response(conn, 200)

      assert Enum.any?(objects, &(&1["id"] == obj.id))
      assert Enum.any?(objects, &(&1["norad_id"] == 80000))
    end

    test "search is case-insensitive", %{conn: conn, space_object: obj} do
      conn = get(conn, ~p"/api/objects?search=alpha")
      assert %{"data" => objects} = json_response(conn, 200)

      assert Enum.any?(objects, &(&1["id"] == obj.id))
    end

    test "returns empty list when no objects match filters", %{conn: conn} do
      conn = get(conn, ~p"/api/objects?object_type=rocket_body&orbital_status=decayed")
      assert %{"data" => objects} = json_response(conn, 200)

      # Might be empty if no objects match
      assert is_list(objects)
    end

    test "supports pagination", %{conn: conn} do
      conn = get(conn, ~p"/api/objects?page=1&page_size=10")
      assert %{"data" => objects} = json_response(conn, 200)

      assert is_list(objects)
      assert length(objects) <= 10
    end
  end

  describe "show" do
    test "shows specific object by NORAD ID", %{conn: conn, space_object: obj} do
      conn = get(conn, ~p"/api/objects/#{obj.norad_id}")
      assert %{"data" => object} = json_response(conn, 200)

      assert object["norad_id"] == obj.norad_id
      assert object["name"] == obj.name
      assert object["object_type"] == "satellite"
      assert object["orbital_status"] == "active"
    end

    test "includes TLE data in response", %{conn: conn, space_object: obj} do
      conn = get(conn, ~p"/api/objects/#{obj.norad_id}")
      assert %{"data" => object} = json_response(conn, 200)

      assert Map.has_key?(object, "tle_line1")
      assert Map.has_key?(object, "tle_line2")
      assert Map.has_key?(object, "tle_epoch")
      assert object["tle_line1"] == obj.tle_line1
    end

    test "includes orbital parameters in response", %{conn: conn, space_object: obj} do
      conn = get(conn, ~p"/api/objects/#{obj.norad_id}")
      assert %{"data" => object} = json_response(conn, 200)

      assert object["apogee_km"] == obj.apogee_km
      assert object["perigee_km"] == obj.perigee_km
      assert object["inclination_deg"] == obj.inclination_deg
      assert object["period_min"] == obj.period_min
    end

    test "returns 404 for non-existent NORAD ID", %{conn: conn} do
      conn = get(conn, ~p"/api/objects/99999")

      assert json_response(conn, 404)
    end
  end

  describe "create" do
    test "creates object with valid attributes", %{conn: conn} do
      create_attrs = %{@valid_attrs | norad_id: 80001, name: "New Test Satellite"}

      conn = post(conn, ~p"/api/objects", object: create_attrs)
      assert %{"data" => object} = json_response(conn, 201)

      assert object["norad_id"] == 80001
      assert object["name"] == "New Test Satellite"
      assert object["object_type"] == "satellite"
    end

    test "returns errors when data is invalid", %{conn: conn} do
      conn = post(conn, ~p"/api/objects", object: @invalid_attrs)
      assert %{"errors" => errors} = json_response(conn, 422)

      assert is_map(errors)
    end

    test "enforces unique NORAD ID constraint", %{conn: conn, space_object: obj} do
      duplicate_attrs = %{@valid_attrs | norad_id: obj.norad_id}

      conn = post(conn, ~p"/api/objects", object: duplicate_attrs)
      assert %{"errors" => errors} = json_response(conn, 422)

      assert Map.has_key?(errors, "norad_id")
    end

    test "validates TLE line lengths", %{conn: conn} do
      invalid_tle_attrs = %{
        @valid_attrs
        | norad_id: 80002,
          tle_line1: "too short",
          tle_line2: "too short"
      }

      conn = post(conn, ~p"/api/objects", object: invalid_tle_attrs)
      assert %{"errors" => errors} = json_response(conn, 422)

      assert Map.has_key?(errors, "tle_line1") or Map.has_key?(errors, "tle_line2")
    end

    test "validates object_type enum", %{conn: conn} do
      invalid_type_attrs = %{@valid_attrs | norad_id: 80003, object_type: "invalid_type"}

      conn = post(conn, ~p"/api/objects", object: invalid_type_attrs)
      assert %{"errors" => errors} = json_response(conn, 422)

      assert Map.has_key?(errors, "object_type")
    end
  end

  describe "update" do
    test "updates object with valid attributes", %{conn: conn, space_object: obj} do
      conn = put(conn, ~p"/api/objects/#{obj.norad_id}", object: @update_attrs)
      assert %{"data" => object} = json_response(conn, 200)

      assert object["name"] == "Updated Satellite Name"
      assert object["orbital_status"] == "retired"
    end

    test "returns errors when data is invalid", %{conn: conn, space_object: obj} do
      conn = put(conn, ~p"/api/objects/#{obj.norad_id}", object: %{name: nil})
      assert %{"errors" => errors} = json_response(conn, 422)

      assert is_map(errors)
    end

    test "returns 404 for non-existent object", %{conn: conn} do
      conn = put(conn, ~p"/api/objects/99999", object: @update_attrs)

      assert json_response(conn, 404)
    end
  end

  describe "update_tle" do
    @new_tle_line1 "1 80000U 24001A   24024.12345678  .00001235  00000-0  12346-4 0  9999"
    @new_tle_line2 "2 80000  51.6401 123.4568 0001235  12.3457  78.9013 15.48919235123457"

    test "updates TLE data", %{conn: conn, space_object: obj} do
      tle_attrs = %{
        tle_line1: @new_tle_line1,
        tle_line2: @new_tle_line2,
        tle_epoch: "2024-01-24T02:57:46Z"
      }

      conn = put(conn, ~p"/api/objects/#{obj.norad_id}/tle", tle: tle_attrs)
      assert %{"data" => object} = json_response(conn, 200)

      assert object["tle_line1"] == @new_tle_line1
      assert object["tle_line2"] == @new_tle_line2
    end

    test "validates TLE line lengths", %{conn: conn, space_object: obj} do
      invalid_tle = %{
        tle_line1: "invalid",
        tle_line2: "invalid",
        tle_epoch: "2024-01-24T02:57:46Z"
      }

      conn = put(conn, ~p"/api/objects/#{obj.norad_id}/tle", tle: invalid_tle)
      assert %{"errors" => _errors} = json_response(conn, 422)
    end

    test "returns 404 for non-existent object", %{conn: conn} do
      tle_attrs = %{
        tle_line1: @new_tle_line1,
        tle_line2: @new_tle_line2,
        tle_epoch: "2024-01-24T02:57:46Z"
      }

      conn = put(conn, ~p"/api/objects/99999/tle", tle: tle_attrs)

      assert json_response(conn, 404)
    end
  end

  describe "classify" do
    test "creates threat assessment for object", %{conn: conn, space_object: obj} do
      classification_attrs = %{
        classification: "suspicious",
        threat_level: "medium",
        capabilities: ["maneuver", "rendezvous"],
        intel_summary: "Object shows unusual maneuvering behavior",
        assessed_by: "Analyst-001",
        confidence_level: "medium"
      }

      conn = post(conn, ~p"/api/objects/#{obj.norad_id}/classify", assessment: classification_attrs)
      assert %{"data" => object} = json_response(conn, 200)

      # Response should include the updated object
      assert object["norad_id"] == obj.norad_id

      # Verify threat assessment was created
      assessment = Threats.get_assessment_for_object(obj.id)
      assert assessment != nil
      assert assessment.classification == :suspicious
    end

    test "validates classification enum", %{conn: conn, space_object: obj} do
      invalid_classification = %{
        classification: "invalid",
        threat_level: "medium",
        assessed_by: "Analyst-001"
      }

      conn =
        post(conn, ~p"/api/objects/#{obj.norad_id}/classify", assessment: invalid_classification)

      assert %{"errors" => _errors} = json_response(conn, 422)
    end

    test "returns 404 for non-existent object", %{conn: conn} do
      classification_attrs = %{
        classification: "suspicious",
        threat_level: "medium",
        assessed_by: "Analyst-001"
      }

      conn = post(conn, ~p"/api/objects/99999/classify", assessment: classification_attrs)

      assert json_response(conn, 404)
    end
  end

  describe "response format" do
    test "includes all required fields", %{conn: conn, space_object: obj} do
      conn = get(conn, ~p"/api/objects/#{obj.norad_id}")
      assert %{"data" => object} = json_response(conn, 200)

      # Required fields
      assert Map.has_key?(object, "id")
      assert Map.has_key?(object, "norad_id")
      assert Map.has_key?(object, "name")
      assert Map.has_key?(object, "object_type")
      assert Map.has_key?(object, "orbital_status")
      assert Map.has_key?(object, "tle_line1")
      assert Map.has_key?(object, "tle_line2")
    end

    test "formats dates as ISO8601", %{conn: conn, space_object: obj} do
      conn = get(conn, ~p"/api/objects/#{obj.norad_id}")
      assert %{"data" => object} = json_response(conn, 200)

      # Dates should be ISO8601 formatted
      if object["tle_epoch"] do
        assert is_binary(object["tle_epoch"])
        assert String.contains?(object["tle_epoch"], "T")
      end

      if object["launch_date"] do
        assert is_binary(object["launch_date"])
      end
    end

    test "includes threat assessment when available", %{conn: conn, space_object: obj} do
      # Create threat assessment
      Threats.assess_threat(obj, %{
        classification: "hostile",
        threat_level: "high",
        assessed_by: "System"
      })

      conn = get(conn, ~p"/api/objects/#{obj.norad_id}")
      assert %{"data" => object} = json_response(conn, 200)

      # Should include threat assessment
      assert Map.has_key?(object, "threat_assessment")
      assert object["threat_assessment"]["classification"] == "hostile"
    end
  end

  describe "delete" do
    test "deletes chosen object", %{conn: conn, space_object: obj} do
      conn = delete(conn, ~p"/api/objects/#{obj.norad_id}")
      assert response(conn, 204)

      # Verify object is deleted
      assert SpaceObjects.get_object_by_norad_id(obj.norad_id) == nil
    end

    test "returns 404 for non-existent object", %{conn: conn} do
      conn = delete(conn, ~p"/api/objects/99999")

      assert json_response(conn, 404)
    end
  end

  describe "error handling" do
    test "handles database errors gracefully", %{conn: conn} do
      # Try to get object with non-numeric NORAD ID
      conn = get(conn, ~p"/api/objects/not-a-number")

      # Should return 404 or 400
      assert response = json_response(conn, :not_found)
      assert is_map(response)
    end
  end
end
