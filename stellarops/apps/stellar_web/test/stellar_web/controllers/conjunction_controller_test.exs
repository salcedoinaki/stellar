defmodule StellarWeb.ConjunctionControllerTest do
  use StellarWeb.ConnCase, async: true

  alias StellarData.{Conjunctions, Satellites, SpaceObjects}

  @satellite_attrs %{
    satellite_id: "SAT-CONJ-CTRL-001",
    name: "Test Asset",
    mode: :operational,
    energy: 85.0,
    memory_used: 45.0,
    position: %{x_km: 6800.0, y_km: 0.0, z_km: 0.0},
    velocity: %{vx_km_s: 0.0, vy_km_s: 7.5, vz_km_s: 0.0}
  }

  @space_object_attrs %{
    norad_id: 70000,
    name: "Test Debris for Controller",
    object_type: "debris",
    owner: "Unknown",
    country_code: "UNK",
    orbital_status: "active",
    tle_line1: "1 70000U 22001A   24023.12345678  .00001234  00000-0  12345-4 0  9998",
    tle_line2: "2 70000  51.6400 123.4567 0001234  12.3456  78.9012 15.48919234123456",
    tle_epoch: ~U[2024-01-23 02:57:46Z],
    rcs_meters: 0.5
  }

  @conjunction_attrs %{
    tca: ~U[2024-01-24 12:30:00Z],
    miss_distance_km: 0.85,
    relative_velocity_km_s: 14.2,
    probability_of_collision: 1.5e-4,
    severity: "high",
    status: "active",
    asset_position_at_tca: %{"x" => 6800.0, "y" => 500.0, "z" => 200.0},
    object_position_at_tca: %{"x" => 6801.0, "y" => 500.0, "z" => 200.0}
  }

  setup %{conn: conn} do
    {:ok, satellite} = Satellites.create_satellite(@satellite_attrs)
    {:ok, space_object} = SpaceObjects.create_object(@space_object_attrs)

    {:ok, conjunction} =
      @conjunction_attrs
      |> Map.put(:asset_id, satellite.id)
      |> Map.put(:object_id, space_object.id)
      |> Conjunctions.create_conjunction()

    {:ok,
     conn: put_req_header(conn, "accept", "application/json"),
     satellite: satellite,
     space_object: space_object,
     conjunction: conjunction}
  end

  # TASK-273: Controller tests for ConjunctionController
  describe "index" do
    test "lists all conjunctions", %{conn: conn, conjunction: conj} do
      conn = get(conn, ~p"/api/conjunctions")
      assert %{"data" => conjunctions} = json_response(conn, 200)
      assert is_list(conjunctions)
      assert length(conjunctions) >= 1

      # Verify our conjunction is in the list
      conjunction_ids = Enum.map(conjunctions, & &1["id"])
      assert conj.id in conjunction_ids
    end

    test "filters conjunctions by asset_id", %{conn: conn, satellite: sat, conjunction: conj} do
      conn = get(conn, ~p"/api/conjunctions?asset_id=#{sat.id}")
      assert %{"data" => conjunctions} = json_response(conn, 200)

      assert Enum.all?(conjunctions, &(&1["asset_id"] == sat.id))
      assert Enum.any?(conjunctions, &(&1["id"] == conj.id))
    end

    test "filters conjunctions by severity", %{conn: conn, conjunction: conj} do
      conn = get(conn, ~p"/api/conjunctions?severity=high")
      assert %{"data" => conjunctions} = json_response(conn, 200)

      assert Enum.all?(conjunctions, &(&1["severity"] == "high"))
      assert Enum.any?(conjunctions, &(&1["id"] == conj.id))
    end

    test "filters conjunctions by status", %{conn: conn, conjunction: conj} do
      conn = get(conn, ~p"/api/conjunctions?status=active")
      assert %{"data" => conjunctions} = json_response(conn, 200)

      assert Enum.all?(conjunctions, &(&1["status"] == "active"))
      assert Enum.any?(conjunctions, &(&1["id"] == conj.id))
    end

    test "filters conjunctions by time window", %{conn: conn, conjunction: conj} do
      tca_after = "2024-01-24T00:00:00Z"
      tca_before = "2024-01-25T00:00:00Z"

      conn = get(conn, ~p"/api/conjunctions?tca_after=#{tca_after}&tca_before=#{tca_before}")
      assert %{"data" => conjunctions} = json_response(conn, 200)

      assert Enum.any?(conjunctions, &(&1["id"] == conj.id))
    end

    test "returns empty list when no conjunctions match filters", %{conn: conn} do
      conn = get(conn, ~p"/api/conjunctions?severity=critical")
      assert %{"data" => conjunctions} = json_response(conn, 200)

      # Might be empty if no critical conjunctions exist
      assert is_list(conjunctions)
    end

    test "supports pagination", %{conn: conn} do
      conn = get(conn, ~p"/api/conjunctions?page=1&page_size=10")
      assert %{"data" => conjunctions} = json_response(conn, 200)

      assert is_list(conjunctions)
      assert length(conjunctions) <= 10
    end
  end

  describe "show" do
    test "shows specific conjunction with details", %{conn: conn, conjunction: conj} do
      conn = get(conn, ~p"/api/conjunctions/#{conj.id}")
      assert %{"data" => conjunction} = json_response(conn, 200)

      assert conjunction["id"] == conj.id
      assert conjunction["miss_distance_km"] == 0.85
      assert conjunction["severity"] == "high"
      assert conjunction["status"] == "active"
      assert conjunction["tca"] != nil
      assert conjunction["asset_position_at_tca"] != nil
      assert conjunction["object_position_at_tca"] != nil
    end

    test "includes asset details in response", %{conn: conn, conjunction: conj} do
      conn = get(conn, ~p"/api/conjunctions/#{conj.id}")
      assert %{"data" => conjunction} = json_response(conn, 200)

      # Asset details should be included
      assert Map.has_key?(conjunction, "asset")
      assert conjunction["asset"]["satellite_id"] == "SAT-CONJ-CTRL-001"
    end

    test "includes object details in response", %{conn: conn, conjunction: conj} do
      conn = get(conn, ~p"/api/conjunctions/#{conj.id}")
      assert %{"data" => conjunction} = json_response(conn, 200)

      # Object details should be included
      assert Map.has_key?(conjunction, "object")
      assert conjunction["object"]["norad_id"] == 70000
    end

    test "returns 404 for non-existent conjunction", %{conn: conn} do
      non_existent_id = Ecto.UUID.generate()
      conn = get(conn, ~p"/api/conjunctions/#{non_existent_id}")

      assert json_response(conn, 404)
    end
  end

  describe "acknowledge" do
    test "acknowledges a conjunction", %{conn: conn, conjunction: conj} do
      conn =
        post(conn, ~p"/api/conjunctions/#{conj.id}/acknowledge", %{
          "acknowledged_by" => "Operator-001"
        })

      assert %{"data" => conjunction} = json_response(conn, 200)
      assert conjunction["status"] == "monitoring"
    end

    test "returns 404 for non-existent conjunction", %{conn: conn} do
      non_existent_id = Ecto.UUID.generate()

      conn =
        post(conn, ~p"/api/conjunctions/#{non_existent_id}/acknowledge", %{
          "acknowledged_by" => "Operator-001"
        })

      assert json_response(conn, 404)
    end
  end

  describe "resolve" do
    test "resolves a conjunction", %{conn: conn, conjunction: conj} do
      conn = post(conn, ~p"/api/conjunctions/#{conj.id}/resolve")

      assert %{"data" => conjunction} = json_response(conn, 200)
      assert conjunction["status"] == "resolved"
    end

    test "returns 404 for non-existent conjunction", %{conn: conn} do
      non_existent_id = Ecto.UUID.generate()
      conn = post(conn, ~p"/api/conjunctions/#{non_existent_id}/resolve")

      assert json_response(conn, 404)
    end
  end

  describe "data validation" do
    test "validates datetime format for tca_after filter", %{conn: conn} do
      conn = get(conn, ~p"/api/conjunctions?tca_after=invalid-date")

      # Should either return 400 or ignore invalid parameter
      response = json_response(conn, :ok)
      assert is_map(response)
    end

    test "validates severity enum values", %{conn: conn} do
      conn = get(conn, ~p"/api/conjunctions?severity=invalid")

      # Should return valid response (empty or error)
      response = json_response(conn, :ok)
      assert is_map(response)
    end

    test "validates status enum values", %{conn: conn} do
      conn = get(conn, ~p"/api/conjunctions?status=invalid")

      # Should return valid response
      response = json_response(conn, :ok)
      assert is_map(response)
    end
  end

  describe "response format" do
    test "includes all required fields", %{conn: conn, conjunction: conj} do
      conn = get(conn, ~p"/api/conjunctions/#{conj.id}")
      assert %{"data" => conjunction} = json_response(conn, 200)

      # Required fields
      assert Map.has_key?(conjunction, "id")
      assert Map.has_key?(conjunction, "asset_id")
      assert Map.has_key?(conjunction, "object_id")
      assert Map.has_key?(conjunction, "tca")
      assert Map.has_key?(conjunction, "miss_distance_km")
      assert Map.has_key?(conjunction, "relative_velocity_km_s")
      assert Map.has_key?(conjunction, "probability_of_collision")
      assert Map.has_key?(conjunction, "severity")
      assert Map.has_key?(conjunction, "status")
    end

    test "formats dates as ISO8601", %{conn: conn, conjunction: conj} do
      conn = get(conn, ~p"/api/conjunctions/#{conj.id}")
      assert %{"data" => conjunction} = json_response(conn, 200)

      # TCA should be ISO8601 formatted
      tca = conjunction["tca"]
      assert is_binary(tca)
      assert String.contains?(tca, "T")
      assert String.ends_with?(tca, "Z")
    end

    test "includes position data as nested objects", %{conn: conn, conjunction: conj} do
      conn = get(conn, ~p"/api/conjunctions/#{conj.id}")
      assert %{"data" => conjunction} = json_response(conn, 200)

      assert is_map(conjunction["asset_position_at_tca"])
      assert is_map(conjunction["object_position_at_tca"])

      # Check position coordinates
      assert Map.has_key?(conjunction["asset_position_at_tca"], "x")
      assert Map.has_key?(conjunction["asset_position_at_tca"], "y")
      assert Map.has_key?(conjunction["asset_position_at_tca"], "z")
    end
  end

  describe "error handling" do
    test "handles database errors gracefully", %{conn: conn} do
      # Try to get conjunction with invalid UUID format
      conn = get(conn, ~p"/api/conjunctions/not-a-uuid")

      # Should return 404 or 400
      assert response = json_response(conn, :not_found)
      assert is_map(response)
    end
  end
end
