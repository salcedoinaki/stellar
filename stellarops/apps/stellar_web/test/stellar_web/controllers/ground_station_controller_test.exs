defmodule StellarWeb.GroundStationControllerTest do
  @moduledoc """
  Controller tests for ground station endpoints.
  
  TASK-120: Write controller tests for all ground station endpoints
  """

  use StellarWeb.ConnCase

  alias StellarData.GroundStations

  # Test helper to create a ground station directly
  defp create_ground_station(attrs) do
    default_attrs = %{
      name: "Test Station",
      location: "Test Location",
      latitude: 40.0,
      longitude: -105.0,
      altitude_m: 1650.0,
      status: :online,
      max_bandwidth_mbps: 100.0
    }

    GroundStations.create_ground_station(Map.merge(default_attrs, attrs))
  end

  describe "GET /api/ground_stations" do
    @tag :db_required
    test "returns list of ground stations", %{conn: conn} do
      {:ok, station} = create_ground_station(%{name: "Boulder Station"})

      conn = get(conn, "/api/ground_stations")

      response = json_response(conn, 200)
      names = Enum.map(response["data"], & &1["name"])
      assert "Boulder Station" in names
    end

    @tag :db_required
    test "returns empty list when no stations exist", %{conn: conn} do
      conn = get(conn, "/api/ground_stations")

      response = json_response(conn, 200)
      assert is_list(response["data"])
    end
  end

  describe "GET /api/ground_stations/:id" do
    @tag :db_required
    test "returns ground station when exists", %{conn: conn} do
      {:ok, station} = create_ground_station(%{name: "Show Station"})

      conn = get(conn, "/api/ground_stations/#{station.id}")

      response = json_response(conn, 200)
      assert response["data"]["id"] == station.id
      assert response["data"]["name"] == "Show Station"
    end

    @tag :db_required
    test "returns 404 for non-existent station", %{conn: conn} do
      conn = get(conn, "/api/ground_stations/#{Ecto.UUID.generate()}")

      assert json_response(conn, 404)
    end
  end

  describe "POST /api/ground_stations" do
    @tag :db_required
    test "creates ground station with valid params", %{conn: conn} do
      params = %{
        "ground_station" => %{
          "name" => "New Station",
          "location" => "Denver, CO",
          "latitude" => 39.7392,
          "longitude" => -104.9903,
          "altitude_m" => 1609.0,
          "max_bandwidth_mbps" => 150.0
        }
      }

      conn = post(conn, "/api/ground_stations", params)

      response = json_response(conn, 201)
      assert response["data"]["name"] == "New Station"
      assert response["data"]["location"] == "Denver, CO"
    end

    @tag :db_required
    test "returns 422 for invalid params", %{conn: conn} do
      params = %{
        "ground_station" => %{
          # Missing required fields
          "latitude" => 40.0
        }
      }

      conn = post(conn, "/api/ground_stations", params)

      assert json_response(conn, 422)
    end

    @tag :db_required
    test "creates station with all optional fields", %{conn: conn} do
      params = %{
        "ground_station" => %{
          "name" => "Full Station",
          "location" => "Fairbanks, AK",
          "latitude" => 64.8378,
          "longitude" => -147.7164,
          "altitude_m" => 136.0,
          "max_bandwidth_mbps" => 200.0,
          "min_elevation_deg" => 5.0,
          "status" => "online",
          "description" => "High-latitude tracking station"
        }
      }

      conn = post(conn, "/api/ground_stations", params)

      response = json_response(conn, 201)
      assert response["data"]["status"] == "online"
    end
  end

  describe "PATCH /api/ground_stations/:id" do
    @tag :db_required
    test "updates ground station", %{conn: conn} do
      {:ok, station} = create_ground_station(%{name: "Original Name"})

      params = %{
        "ground_station" => %{
          "name" => "Updated Name",
          "max_bandwidth_mbps" => 200.0
        }
      }

      conn = patch(conn, "/api/ground_stations/#{station.id}", params)

      response = json_response(conn, 200)
      assert response["data"]["name"] == "Updated Name"
      assert response["data"]["max_bandwidth_mbps"] == 200.0
    end

    @tag :db_required
    test "returns 404 for non-existent station", %{conn: conn} do
      params = %{"ground_station" => %{"name" => "New Name"}}
      conn = patch(conn, "/api/ground_stations/#{Ecto.UUID.generate()}", params)

      assert json_response(conn, 404)
    end

    @tag :db_required
    test "returns 422 for invalid update", %{conn: conn} do
      {:ok, station} = create_ground_station(%{name: "Valid Station"})

      params = %{
        "ground_station" => %{
          "latitude" => "invalid"  # Should be numeric
        }
      }

      conn = patch(conn, "/api/ground_stations/#{station.id}", params)

      assert json_response(conn, 422)
    end
  end

  describe "DELETE /api/ground_stations/:id" do
    @tag :db_required
    test "deletes ground station", %{conn: conn} do
      {:ok, station} = create_ground_station(%{name: "To Delete"})

      conn = delete(conn, "/api/ground_stations/#{station.id}")

      assert response(conn, 204)
      
      # Verify it's deleted
      assert GroundStations.get_ground_station(station.id) == nil
    end

    @tag :db_required
    test "returns 404 for non-existent station", %{conn: conn} do
      conn = delete(conn, "/api/ground_stations/#{Ecto.UUID.generate()}")

      assert json_response(conn, 404)
    end
  end

  describe "PATCH /api/ground_stations/:id/status" do
    @tag :db_required
    test "sets station to online", %{conn: conn} do
      {:ok, station} = create_ground_station(%{name: "Offline Station", status: :offline})

      conn = patch(conn, "/api/ground_stations/#{station.id}/status", %{"status" => "online"})

      response = json_response(conn, 200)
      assert response["data"]["status"] == "online"
    end

    @tag :db_required
    test "sets station to offline", %{conn: conn} do
      {:ok, station} = create_ground_station(%{name: "Online Station", status: :online})

      conn = patch(conn, "/api/ground_stations/#{station.id}/status", %{"status" => "offline"})

      response = json_response(conn, 200)
      assert response["data"]["status"] == "offline"
    end

    @tag :db_required
    test "sets station to maintenance", %{conn: conn} do
      {:ok, station} = create_ground_station(%{name: "Maint Station", status: :online})

      conn = patch(conn, "/api/ground_stations/#{station.id}/status", %{"status" => "maintenance"})

      response = json_response(conn, 200)
      assert response["data"]["status"] == "maintenance"
    end

    @tag :db_required
    test "returns 404 for non-existent station", %{conn: conn} do
      conn = patch(conn, "/api/ground_stations/#{Ecto.UUID.generate()}/status", %{"status" => "online"})

      assert json_response(conn, 404)
    end
  end

  describe "GET /api/ground_stations/bandwidth" do
    @tag :db_required
    test "returns total available bandwidth", %{conn: conn} do
      conn = get(conn, "/api/ground_stations/bandwidth")

      response = json_response(conn, 200)
      assert Map.has_key?(response, "available_bandwidth_mbps")
      assert is_number(response["available_bandwidth_mbps"])
    end
  end

  describe "GET /api/ground_stations/:id/windows" do
    @tag :db_required
    test "returns contact windows for station", %{conn: conn} do
      {:ok, station} = create_ground_station(%{name: "Window Station"})

      conn = get(conn, "/api/ground_stations/#{station.id}/windows")

      response = json_response(conn, 200)
      assert Map.has_key?(response, "data")
      assert is_list(response["data"])
    end

    @tag :db_required
    test "accepts hours parameter", %{conn: conn} do
      {:ok, station} = create_ground_station(%{name: "Hours Station"})

      conn = get(conn, "/api/ground_stations/#{station.id}/windows", %{"hours" => "48"})

      response = json_response(conn, 200)
      assert is_list(response["data"])
    end

    @tag :db_required
    test "accepts start time parameter", %{conn: conn} do
      {:ok, station} = create_ground_station(%{name: "Start Station"})
      start_time = DateTime.utc_now() |> DateTime.to_iso8601()

      conn = get(conn, "/api/ground_stations/#{station.id}/windows", %{"start" => start_time})

      response = json_response(conn, 200)
      assert is_list(response["data"])
    end
  end
end
