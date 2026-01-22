defmodule StellarWeb.AlarmControllerTest do
  @moduledoc """
  Controller tests for alarm endpoints.
  
  TASK-121: Write controller tests for all alarm endpoints
  """

  use StellarWeb.ConnCase

  alias StellarCore.Alarms

  setup do
    # Clear alarms before each test
    if :ets.whereis(:stellar_alarms) != :undefined do
      :ets.delete_all_objects(:stellar_alarms)
    end

    :ok
  end

  # Helper to create an alarm directly
  defp create_test_alarm(type, severity, message, source \\ "test:controller") do
    Alarms.raise_alarm(type, severity, message, source, %{test: true})
  end

  describe "GET /api/alarms" do
    test "returns empty list when no alarms exist", %{conn: conn} do
      conn = get(conn, "/api/alarms")

      response = json_response(conn, 200)
      assert response["data"] == []
    end

    test "returns list of alarms", %{conn: conn} do
      {:ok, alarm1} = create_test_alarm("test_type1", :major, "First alarm")
      {:ok, alarm2} = create_test_alarm("test_type2", :warning, "Second alarm")

      conn = get(conn, "/api/alarms")

      response = json_response(conn, 200)
      ids = Enum.map(response["data"], & &1["id"])
      
      assert alarm1.id in ids
      assert alarm2.id in ids
    end

    test "filters by status", %{conn: conn} do
      {:ok, active} = create_test_alarm("active_alarm", :major, "Active")
      {:ok, resolved} = create_test_alarm("resolved_alarm", :major, "Resolved")
      Alarms.resolve(resolved.id)

      conn = get(conn, "/api/alarms", %{"status" => "active"})

      response = json_response(conn, 200)
      ids = Enum.map(response["data"], & &1["id"])
      
      assert active.id in ids
      refute resolved.id in ids
    end

    test "filters by severity", %{conn: conn} do
      {:ok, critical} = create_test_alarm("critical_alarm", :critical, "Critical")
      {:ok, _warning} = create_test_alarm("warning_alarm", :warning, "Warning")

      conn = get(conn, "/api/alarms", %{"severity" => "critical"})

      response = json_response(conn, 200)
      ids = Enum.map(response["data"], & &1["id"])
      
      assert critical.id in ids
    end

    test "filters by source prefix", %{conn: conn} do
      {:ok, sat_alarm} = create_test_alarm("sat_alarm", :major, "Sat", "satellite:SAT-001")
      {:ok, _mission_alarm} = create_test_alarm("mission_alarm", :major, "Mission", "mission:M-001")

      conn = get(conn, "/api/alarms", %{"source" => "satellite"})

      response = json_response(conn, 200)
      ids = Enum.map(response["data"], & &1["id"])
      
      assert sat_alarm.id in ids
    end

    test "respects limit parameter", %{conn: conn} do
      for i <- 1..10 do
        create_test_alarm("limit_alarm_#{i}", :minor, "Alarm #{i}")
      end

      conn = get(conn, "/api/alarms", %{"limit" => "5"})

      response = json_response(conn, 200)
      assert length(response["data"]) <= 5
    end
  end

  describe "GET /api/alarms/summary" do
    test "returns alarm summary", %{conn: conn} do
      {:ok, _} = create_test_alarm("sum1", :critical, "Critical")
      {:ok, _} = create_test_alarm("sum2", :major, "Major")
      {:ok, alarm3} = create_test_alarm("sum3", :warning, "Warning")
      Alarms.resolve(alarm3.id)

      conn = get(conn, "/api/alarms/summary")

      response = json_response(conn, 200)
      assert Map.has_key?(response, "total")
      assert Map.has_key?(response, "by_status")
      assert Map.has_key?(response, "by_severity")
    end

    test "returns correct counts", %{conn: conn} do
      {:ok, _} = create_test_alarm("count1", :critical, "One")
      {:ok, _} = create_test_alarm("count2", :critical, "Two")

      conn = get(conn, "/api/alarms/summary")

      response = json_response(conn, 200)
      assert response["total"] >= 2
    end
  end

  describe "GET /api/alarms/:id" do
    test "returns alarm when exists", %{conn: conn} do
      {:ok, alarm} = create_test_alarm("show_alarm", :major, "Show me")

      conn = get(conn, "/api/alarms/#{alarm.id}")

      response = json_response(conn, 200)
      assert response["data"]["id"] == alarm.id
      assert response["data"]["type"] == "show_alarm"
      assert response["data"]["severity"] == "major"
    end

    test "returns 404 for non-existent alarm", %{conn: conn} do
      conn = get(conn, "/api/alarms/nonexistent-id")

      assert json_response(conn, 404)
    end
  end

  describe "POST /api/alarms/:id/acknowledge" do
    test "acknowledges an active alarm", %{conn: conn} do
      {:ok, alarm} = create_test_alarm("ack_alarm", :major, "Acknowledge me")

      conn = post(conn, "/api/alarms/#{alarm.id}/acknowledge", %{"user" => "operator@test.com"})

      response = json_response(conn, 200)
      assert response["data"]["status"] == "acknowledged"
      assert response["data"]["acknowledged_by"] == "operator@test.com"
    end

    test "uses default user when not provided", %{conn: conn} do
      {:ok, alarm} = create_test_alarm("ack_default", :minor, "Default ack")

      conn = post(conn, "/api/alarms/#{alarm.id}/acknowledge")

      response = json_response(conn, 200)
      assert response["data"]["status"] == "acknowledged"
      assert response["data"]["acknowledged_by"] == "api"
    end

    test "returns 404 for non-existent alarm", %{conn: conn} do
      conn = post(conn, "/api/alarms/nonexistent-id/acknowledge")

      assert json_response(conn, 404)
    end
  end

  describe "POST /api/alarms/:id/resolve" do
    test "resolves an active alarm", %{conn: conn} do
      {:ok, alarm} = create_test_alarm("resolve_alarm", :major, "Resolve me")

      conn = post(conn, "/api/alarms/#{alarm.id}/resolve")

      response = json_response(conn, 200)
      assert response["data"]["status"] == "resolved"
      assert response["data"]["resolved_at"] != nil
    end

    test "resolves an acknowledged alarm", %{conn: conn} do
      {:ok, alarm} = create_test_alarm("ack_resolve", :major, "Ack then resolve")
      Alarms.acknowledge(alarm.id, "user")

      conn = post(conn, "/api/alarms/#{alarm.id}/resolve")

      response = json_response(conn, 200)
      assert response["data"]["status"] == "resolved"
    end

    test "returns 404 for non-existent alarm", %{conn: conn} do
      conn = post(conn, "/api/alarms/nonexistent-id/resolve")

      assert json_response(conn, 404)
    end
  end

  describe "POST /api/alarms" do
    test "creates a test alarm", %{conn: conn} do
      params = %{
        "type" => "test_alarm",
        "severity" => "warning",
        "message" => "This is a test alarm",
        "source" => "api:test",
        "details" => %{"key" => "value"}
      }

      conn = post(conn, "/api/alarms", params)

      response = json_response(conn, 201)
      assert response["data"]["type"] == "test_alarm"
      assert response["data"]["severity"] == "warning"
      assert response["data"]["status"] == "active"
    end

    test "creates alarm with all severity levels", %{conn: conn} do
      for severity <- ["critical", "major", "minor", "warning", "info"] do
        params = %{
          "type" => "severity_test_#{severity}",
          "severity" => severity,
          "message" => "Testing #{severity}"
        }

        conn = post(conn, "/api/alarms", params)
        response = json_response(conn, 201)
        assert response["data"]["severity"] == severity
      end
    end

    test "returns 400 for invalid severity", %{conn: conn} do
      params = %{
        "type" => "invalid_severity",
        "severity" => "invalid",
        "message" => "Should fail"
      }

      conn = post(conn, "/api/alarms", params)

      assert json_response(conn, 400)
    end
  end

  describe "POST /api/alarms/clear_resolved" do
    test "clears old resolved alarms", %{conn: conn} do
      {:ok, alarm} = create_test_alarm("to_clear", :minor, "Clear me")
      Alarms.resolve(alarm.id)

      conn = post(conn, "/api/alarms/clear_resolved", %{"older_than_seconds" => "0"})

      response = json_response(conn, 200)
      assert Map.has_key?(response, "cleared")
      assert is_integer(response["cleared"])
    end

    test "uses default age when not provided", %{conn: conn} do
      conn = post(conn, "/api/alarms/clear_resolved")

      response = json_response(conn, 200)
      assert Map.has_key?(response, "cleared")
    end
  end

  describe "alarm lifecycle through API" do
    test "full lifecycle: create → acknowledge → resolve", %{conn: conn} do
      # Create
      create_params = %{
        "type" => "lifecycle_test",
        "severity" => "major",
        "message" => "Full lifecycle test"
      }

      conn = post(conn, "/api/alarms", create_params)
      create_response = json_response(conn, 201)
      alarm_id = create_response["data"]["id"]
      assert create_response["data"]["status"] == "active"

      # Acknowledge
      conn = build_conn()
      conn = post(conn, "/api/alarms/#{alarm_id}/acknowledge", %{"user" => "test@example.com"})
      ack_response = json_response(conn, 200)
      assert ack_response["data"]["status"] == "acknowledged"
      assert ack_response["data"]["acknowledged_by"] == "test@example.com"

      # Resolve
      conn = build_conn()
      conn = post(conn, "/api/alarms/#{alarm_id}/resolve")
      resolve_response = json_response(conn, 200)
      assert resolve_response["data"]["status"] == "resolved"

      # Verify final state
      conn = build_conn()
      conn = get(conn, "/api/alarms/#{alarm_id}")
      final_response = json_response(conn, 200)
      assert final_response["data"]["status"] == "resolved"
      assert final_response["data"]["acknowledged_at"] != nil
      assert final_response["data"]["resolved_at"] != nil
    end
  end
end
