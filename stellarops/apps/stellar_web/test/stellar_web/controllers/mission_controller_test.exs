defmodule StellarWeb.MissionControllerTest do
  @moduledoc """
  Controller tests for mission endpoints.
  
  TASK-119: Write controller tests for all mission endpoints
  """

  use StellarWeb.ConnCase

  alias StellarData.Missions
  alias StellarCore.Satellite

  # Test helper to create a mission directly
  defp create_mission(attrs) do
    default_attrs = %{
      name: "Test Mission",
      type: "imaging",
      satellite_id: "TEST-SAT-001",
      priority: :normal,
      required_energy: 10.0,
      required_memory: 5.0
    }

    Missions.create_mission(Map.merge(default_attrs, attrs))
  end

  describe "GET /api/missions" do
    @tag :db_required
    test "returns empty list when no missions exist", %{conn: conn} do
      conn = get(conn, "/api/missions")

      assert json_response(conn, 200)["data"] == []
    end

    @tag :db_required
    test "returns list of missions", %{conn: conn} do
      {:ok, mission1} = create_mission(%{name: "Mission 1", satellite_id: "SAT-001"})
      {:ok, mission2} = create_mission(%{name: "Mission 2", satellite_id: "SAT-002"})

      conn = get(conn, "/api/missions")

      response = json_response(conn, 200)
      assert length(response["data"]) >= 2

      names = Enum.map(response["data"], & &1["name"])
      assert "Mission 1" in names
      assert "Mission 2" in names
    end

    @tag :db_required
    test "filters by status", %{conn: conn} do
      {:ok, _pending} = create_mission(%{name: "Pending", status: :pending})
      {:ok, completed} = create_mission(%{name: "Completed", status: :completed})

      conn = get(conn, "/api/missions", %{"status" => "completed"})

      response = json_response(conn, 200)
      ids = Enum.map(response["data"], & &1["id"])
      assert completed.id in ids
    end

    @tag :db_required
    test "filters by priority", %{conn: conn} do
      {:ok, critical} = create_mission(%{name: "Critical", priority: :critical})
      {:ok, _low} = create_mission(%{name: "Low", priority: :low})

      conn = get(conn, "/api/missions", %{"priority" => "critical"})

      response = json_response(conn, 200)
      ids = Enum.map(response["data"], & &1["id"])
      assert critical.id in ids
    end

    @tag :db_required
    test "filters by satellite_id", %{conn: conn} do
      {:ok, mission} = create_mission(%{name: "SAT-A Mission", satellite_id: "SAT-A"})
      {:ok, _other} = create_mission(%{name: "SAT-B Mission", satellite_id: "SAT-B"})

      conn = get(conn, "/api/missions", %{"satellite_id" => "SAT-A"})

      response = json_response(conn, 200)
      ids = Enum.map(response["data"], & &1["id"])
      assert mission.id in ids
    end
  end

  describe "GET /api/missions/:id" do
    @tag :db_required
    test "returns mission when exists", %{conn: conn} do
      {:ok, mission} = create_mission(%{name: "Show Test Mission"})

      conn = get(conn, "/api/missions/#{mission.id}")

      response = json_response(conn, 200)
      assert response["data"]["id"] == mission.id
      assert response["data"]["name"] == "Show Test Mission"
    end

    @tag :db_required
    test "returns 404 for non-existent mission", %{conn: conn} do
      conn = get(conn, "/api/missions/#{Ecto.UUID.generate()}")

      assert json_response(conn, 404)
    end
  end

  describe "POST /api/missions" do
    @tag :db_required
    test "creates mission with valid params", %{conn: conn} do
      params = %{
        "mission" => %{
          "name" => "New Mission",
          "type" => "imaging",
          "satellite_id" => "SAT-NEW-001",
          "priority" => "high",
          "required_energy" => 15.0
        }
      }

      conn = post(conn, "/api/missions", params)

      response = json_response(conn, 201)
      assert response["data"]["name"] == "New Mission"
      assert response["data"]["status"] == "pending"
    end

    @tag :db_required
    test "returns 422 for invalid params", %{conn: conn} do
      params = %{
        "mission" => %{
          # Missing required fields
          "priority" => "high"
        }
      }

      conn = post(conn, "/api/missions", params)

      assert json_response(conn, 422)
    end

    @tag :db_required
    test "creates mission with all optional fields", %{conn: conn} do
      future = DateTime.add(DateTime.utc_now(), 7200, :second)
      
      params = %{
        "mission" => %{
          "name" => "Full Mission",
          "type" => "data_collection",
          "satellite_id" => "SAT-FULL-001",
          "priority" => "critical",
          "deadline" => DateTime.to_iso8601(future),
          "required_energy" => 20.0,
          "required_memory" => 10.0,
          "required_bandwidth" => 5.0,
          "estimated_duration" => 600,
          "max_retries" => 5,
          "payload" => %{"target" => "region-42"}
        }
      }

      conn = post(conn, "/api/missions", params)

      response = json_response(conn, 201)
      assert response["data"]["priority"] == "critical"
    end
  end

  describe "PATCH /api/missions/:id/cancel" do
    @tag :db_required
    test "cancels a pending mission", %{conn: conn} do
      {:ok, mission} = create_mission(%{name: "To Cancel", status: :pending})

      conn = patch(conn, "/api/missions/#{mission.id}/cancel", %{"reason" => "No longer needed"})

      response = json_response(conn, 200)
      assert response["data"]["status"] == "canceled"
    end

    @tag :db_required
    test "cancels a scheduled mission", %{conn: conn} do
      {:ok, mission} = create_mission(%{name: "Scheduled Cancel", status: :scheduled})

      conn = patch(conn, "/api/missions/#{mission.id}/cancel")

      response = json_response(conn, 200)
      assert response["data"]["status"] == "canceled"
    end

    @tag :db_required
    test "returns 404 for non-existent mission", %{conn: conn} do
      conn = patch(conn, "/api/missions/#{Ecto.UUID.generate()}/cancel")

      assert json_response(conn, 404)
    end

    @tag :db_required
    test "returns 422 when trying to cancel running mission", %{conn: conn} do
      {:ok, mission} = create_mission(%{name: "Running", status: :running})

      conn = patch(conn, "/api/missions/#{mission.id}/cancel")

      assert json_response(conn, 422)
    end
  end

  describe "GET /api/missions/stats" do
    @tag :db_required
    test "returns mission statistics", %{conn: conn} do
      conn = get(conn, "/api/missions/stats")

      response = json_response(conn, 200)
      assert Map.has_key?(response, "by_status")
      assert Map.has_key?(response, "scheduler")
    end
  end

  describe "GET /api/satellites/:satellite_id/missions" do
    @tag :db_required
    test "returns missions for specific satellite", %{conn: conn} do
      {:ok, sat_mission} = create_mission(%{name: "SAT Mission", satellite_id: "TARGET-SAT"})
      {:ok, _other} = create_mission(%{name: "Other Mission", satellite_id: "OTHER-SAT"})

      conn = get(conn, "/api/satellites/TARGET-SAT/missions")

      response = json_response(conn, 200)
      ids = Enum.map(response["data"], & &1["id"])
      assert sat_mission.id in ids
    end

    @tag :db_required
    test "returns empty list for satellite with no missions", %{conn: conn} do
      conn = get(conn, "/api/satellites/NONEXISTENT-SAT/missions")

      response = json_response(conn, 200)
      assert response["data"] == []
    end

    @tag :db_required
    test "filters by status", %{conn: conn} do
      {:ok, completed} = create_mission(%{
        name: "Completed",
        satellite_id: "FILTER-SAT",
        status: :completed
      })
      {:ok, _pending} = create_mission(%{
        name: "Pending",
        satellite_id: "FILTER-SAT",
        status: :pending
      })

      conn = get(conn, "/api/satellites/FILTER-SAT/missions", %{"status" => "completed"})

      response = json_response(conn, 200)
      ids = Enum.map(response["data"], & &1["id"])
      assert completed.id in ids
    end

    @tag :db_required
    test "respects limit parameter", %{conn: conn} do
      for i <- 1..5 do
        create_mission(%{name: "Mission #{i}", satellite_id: "LIMIT-SAT"})
      end

      conn = get(conn, "/api/satellites/LIMIT-SAT/missions", %{"limit" => "3"})

      response = json_response(conn, 200)
      assert length(response["data"]) <= 3
    end
  end
end
