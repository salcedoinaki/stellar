defmodule StellarWeb.SatelliteControllerTest do
  use StellarWeb.ConnCase

  alias StellarCore.Satellite

  describe "GET /api/satellites" do
    test "returns empty list when no satellites exist", %{conn: conn} do
      conn = get(conn, "/api/satellites")

      assert json_response(conn, 200) == %{"data" => []}
    end

    test "returns list of satellites", %{conn: conn} do
      {:ok, _} = Satellite.start("TEST-SAT-001")
      {:ok, _} = Satellite.start("TEST-SAT-002")

      conn = get(conn, "/api/satellites")

      response = json_response(conn, 200)
      assert length(response["data"]) == 2

      ids = Enum.map(response["data"], & &1["id"])
      assert "TEST-SAT-001" in ids
      assert "TEST-SAT-002" in ids
    end
  end

  describe "GET /api/satellites/:id" do
    test "returns satellite state when exists", %{conn: conn} do
      {:ok, _} = Satellite.start("TEST-SAT-003")

      conn = get(conn, "/api/satellites/TEST-SAT-003")

      response = json_response(conn, 200)
      assert response["data"]["id"] == "TEST-SAT-003"
      assert response["data"]["mode"] == "nominal"
      assert response["data"]["energy"] == 100.0
    end

    test "returns 404 when satellite not found", %{conn: conn} do
      conn = get(conn, "/api/satellites/NONEXISTENT")

      response = json_response(conn, 404)
      assert response["error"] == "Satellite not found"
    end
  end

  describe "POST /api/satellites" do
    test "creates a satellite with given id", %{conn: conn} do
      conn = post(conn, "/api/satellites", %{"id" => "NEW-SAT-001"})

      response = json_response(conn, 201)
      assert response["data"]["id"] == "NEW-SAT-001"
      assert response["data"]["mode"] == "nominal"

      # Verify it actually exists
      assert Satellite.alive?("NEW-SAT-001")
    end

    test "creates a satellite with auto-generated id", %{conn: conn} do
      conn = post(conn, "/api/satellites", %{})

      response = json_response(conn, 201)
      assert String.starts_with?(response["data"]["id"], "SAT-")
    end

    test "returns 409 when satellite already exists", %{conn: conn} do
      {:ok, _} = Satellite.start("EXISTING-SAT")

      conn = post(conn, "/api/satellites", %{"id" => "EXISTING-SAT"})

      response = json_response(conn, 409)
      assert response["error"] == "Satellite already exists"
    end
  end

  describe "DELETE /api/satellites/:id" do
    test "stops a running satellite", %{conn: conn} do
      {:ok, _} = Satellite.start("DELETE-SAT-001")
      assert Satellite.alive?("DELETE-SAT-001")

      conn = delete(conn, "/api/satellites/DELETE-SAT-001")

      response = json_response(conn, 200)
      assert response["message"] == "Satellite stopped"

      # Give it time to stop
      :timer.sleep(10)
      refute Satellite.alive?("DELETE-SAT-001")
    end

    test "returns 404 when satellite not found", %{conn: conn} do
      conn = delete(conn, "/api/satellites/NONEXISTENT")

      response = json_response(conn, 404)
      assert response["error"] == "Satellite not found"
    end
  end

  describe "PUT /api/satellites/:id/energy" do
    test "updates satellite energy", %{conn: conn} do
      {:ok, _} = Satellite.start("ENERGY-SAT-001")

      conn = put(conn, "/api/satellites/ENERGY-SAT-001/energy", %{"delta" => -30.0})

      response = json_response(conn, 200)
      assert response["data"]["energy"] == 70.0
    end

    test "returns 400 when delta is missing", %{conn: conn} do
      {:ok, _} = Satellite.start("ENERGY-SAT-002")

      conn = put(conn, "/api/satellites/ENERGY-SAT-002/energy", %{})

      response = json_response(conn, 400)
      assert response["error"] =~ "delta"
    end

    test "returns 404 when satellite not found", %{conn: conn} do
      conn = put(conn, "/api/satellites/NONEXISTENT/energy", %{"delta" => -10.0})

      response = json_response(conn, 404)
      assert response["error"] == "Satellite not found"
    end
  end

  describe "PUT /api/satellites/:id/mode" do
    test "sets satellite mode", %{conn: conn} do
      {:ok, _} = Satellite.start("MODE-SAT-001")

      conn = put(conn, "/api/satellites/MODE-SAT-001/mode", %{"mode" => "safe"})

      response = json_response(conn, 200)
      assert response["data"]["mode"] == "safe"
    end

    test "returns 400 for invalid mode", %{conn: conn} do
      {:ok, _} = Satellite.start("MODE-SAT-002")

      conn = put(conn, "/api/satellites/MODE-SAT-002/mode", %{"mode" => "invalid"})

      response = json_response(conn, 400)
      assert response["error"] =~ "Invalid mode"
    end
  end

  describe "PUT /api/satellites/:id/memory" do
    test "updates satellite memory", %{conn: conn} do
      {:ok, _} = Satellite.start("MEMORY-SAT-001")

      conn = put(conn, "/api/satellites/MEMORY-SAT-001/memory", %{"memory" => 256.0})

      response = json_response(conn, 200)
      assert response["data"]["memory_used"] == 256.0
    end
  end
end
