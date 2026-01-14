defmodule StellarWeb.HealthControllerTest do
  use StellarWeb.ConnCase

  describe "GET /health" do
    test "returns health status", %{conn: conn} do
      conn = get(conn, "/health")

      response = json_response(conn, 200)
      assert response["status"] == "ok"
      assert response["service"] == "stellar_web"
      assert is_integer(response["satellite_count"])
      assert response["timestamp"]
    end
  end
end
