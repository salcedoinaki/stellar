defmodule StellarWeb.ProtectedEndpointsTest do
  @moduledoc """
  Tests for protected API endpoints - verifies authorization is properly enforced.
  """
  
  use StellarWeb.ConnCase, async: true
  
  alias StellarData.Users
  alias StellarWeb.Auth.Guardian
  
  setup do
    # Create users with different roles
    {:ok, admin} = Users.create_user(%{
      email: "admin@stellarops.com",
      password: "SecurePassword123!",
      role: "admin"
    })
    
    {:ok, operator} = Users.create_user(%{
      email: "operator@stellarops.com",
      password: "SecurePassword123!",
      role: "operator"
    })
    
    {:ok, analyst} = Users.create_user(%{
      email: "analyst@stellarops.com",
      password: "SecurePassword123!",
      role: "analyst"
    })
    
    {:ok, viewer} = Users.create_user(%{
      email: "viewer@stellarops.com",
      password: "SecurePassword123!",
      role: "viewer"
    })
    
    {:ok, admin_token, _} = Guardian.encode_and_sign(admin)
    {:ok, operator_token, _} = Guardian.encode_and_sign(operator)
    {:ok, analyst_token, _} = Guardian.encode_and_sign(analyst)
    {:ok, viewer_token, _} = Guardian.encode_and_sign(viewer)
    
    {:ok,
     admin_token: admin_token,
     operator_token: operator_token,
     analyst_token: analyst_token,
     viewer_token: viewer_token}
  end
  
  describe "unauthenticated access" do
    test "GET /api/satellites requires authentication", %{conn: conn} do
      conn = get(conn, ~p"/api/satellites")
      assert conn.status == 401
    end
    
    test "GET /api/missions requires authentication", %{conn: conn} do
      conn = get(conn, ~p"/api/missions")
      assert conn.status == 401
    end
    
    test "GET /api/conjunctions requires authentication", %{conn: conn} do
      conn = get(conn, ~p"/api/conjunctions")
      assert conn.status == 401
    end
    
    test "GET /api/alarms requires authentication", %{conn: conn} do
      conn = get(conn, ~p"/api/alarms")
      assert conn.status == 401
    end
    
    test "GET /health does not require authentication", %{conn: conn} do
      conn = get(conn, ~p"/health")
      assert conn.status == 200
    end
    
    test "GET /metrics does not require authentication", %{conn: conn} do
      conn = get(conn, ~p"/metrics")
      assert conn.status == 200
    end
  end
  
  describe "viewer role access" do
    test "can read satellites", %{conn: conn, viewer_token: token} do
      conn =
        conn
        |> put_req_header("authorization", "Bearer #{token}")
        |> get(~p"/api/satellites")
      
      assert conn.status == 200
    end
    
    test "can read missions", %{conn: conn, viewer_token: token} do
      conn =
        conn
        |> put_req_header("authorization", "Bearer #{token}")
        |> get(~p"/api/missions")
      
      assert conn.status == 200
    end
    
    test "can read alarms", %{conn: conn, viewer_token: token} do
      conn =
        conn
        |> put_req_header("authorization", "Bearer #{token}")
        |> get(~p"/api/alarms")
      
      assert conn.status == 200
    end
    
    test "cannot create missions", %{conn: conn, viewer_token: token} do
      conn =
        conn
        |> put_req_header("authorization", "Bearer #{token}")
        |> post(~p"/api/missions", %{name: "Test", satellite_id: "sat-1"})
      
      assert conn.status == 403
    end
    
    test "cannot acknowledge alarms", %{conn: conn, viewer_token: token} do
      conn =
        conn
        |> put_req_header("authorization", "Bearer #{token}")
        |> post(~p"/api/alarms/alarm-1/acknowledge")
      
      assert conn.status in [403, 404]  # 404 if alarm doesn't exist
    end
  end
  
  describe "analyst role access" do
    test "can classify threats", %{conn: conn, analyst_token: token} do
      conn =
        conn
        |> put_req_header("authorization", "Bearer #{token}")
        |> post(~p"/api/objects/25544/classify", %{
          classification: "hostile",
          threat_level: "high"
        })
      
      # 404 is acceptable if object doesn't exist
      assert conn.status in [200, 404]
    end
    
    test "cannot select COA", %{conn: conn, analyst_token: token} do
      conn =
        conn
        |> put_req_header("authorization", "Bearer #{token}")
        |> post(~p"/api/coas/coa-1/select")
      
      assert conn.status in [403, 404]
    end
  end
  
  describe "operator role access" do
    test "can create missions", %{conn: conn, operator_token: token} do
      conn =
        conn
        |> put_req_header("authorization", "Bearer #{token}")
        |> post(~p"/api/missions", %{
          name: "Test Mission",
          type: "observation",
          satellite_id: "sat-1"
        })
      
      # May succeed or fail validation, but not 403
      assert conn.status != 403
    end
    
    test "can acknowledge alarms", %{conn: conn, operator_token: token} do
      conn =
        conn
        |> put_req_header("authorization", "Bearer #{token}")
        |> post(~p"/api/alarms/alarm-1/acknowledge")
      
      # 404 if alarm doesn't exist, not 403
      assert conn.status in [200, 404]
    end
    
    test "can select COA", %{conn: conn, operator_token: token} do
      conn =
        conn
        |> put_req_header("authorization", "Bearer #{token}")
        |> post(~p"/api/coas/coa-1/select")
      
      # 404 if COA doesn't exist, not 403
      assert conn.status in [200, 404]
    end
    
    test "can classify threats (operator >= analyst)", %{conn: conn, operator_token: token} do
      conn =
        conn
        |> put_req_header("authorization", "Bearer #{token}")
        |> post(~p"/api/objects/25544/classify", %{
          classification: "hostile"
        })
      
      assert conn.status in [200, 404]
    end
  end
  
  describe "admin role access" do
    test "has all permissions", %{conn: conn, admin_token: token} do
      # Admin can access everything
      endpoints = [
        {:get, ~p"/api/satellites"},
        {:get, ~p"/api/missions"},
        {:get, ~p"/api/alarms"},
        {:get, ~p"/api/conjunctions"},
        {:get, ~p"/api/objects"},
      ]
      
      for {method, path} <- endpoints do
        conn =
          conn
          |> put_req_header("authorization", "Bearer #{token}")
          |> apply_method(method, path)
        
        assert conn.status in [200, 404], 
          "#{method} #{path} should succeed, got #{conn.status}"
      end
    end
  end
  
  describe "token validation" do
    test "rejects expired tokens", %{conn: conn} do
      # Create a user and expired token
      {:ok, user} = Users.create_user(%{
        email: "expired@stellarops.com",
        password: "SecurePassword123!",
        role: "viewer"
      })
      
      # Create token that expired 1 hour ago
      {:ok, token, _} = Guardian.encode_and_sign(user, %{}, ttl: {-1, :hour})
      
      conn =
        conn
        |> put_req_header("authorization", "Bearer #{token}")
        |> get(~p"/api/satellites")
      
      assert conn.status == 401
    end
    
    test "rejects malformed tokens", %{conn: conn} do
      conn =
        conn
        |> put_req_header("authorization", "Bearer malformed.token.here")
        |> get(~p"/api/satellites")
      
      assert conn.status == 401
    end
    
    test "rejects revoked tokens", %{conn: conn} do
      {:ok, user} = Users.create_user(%{
        email: "revoked@stellarops.com",
        password: "SecurePassword123!",
        role: "viewer"
      })
      
      {:ok, token, _} = Guardian.encode_and_sign(user)
      
      # Revoke the token
      Guardian.revoke_token(token)
      
      conn =
        conn
        |> put_req_header("authorization", "Bearer #{token}")
        |> get(~p"/api/satellites")
      
      assert conn.status == 401
    end
  end
  
  # Helper to apply HTTP method
  defp apply_method(conn, :get, path), do: get(conn, path)
  defp apply_method(conn, :post, path), do: post(conn, path, %{})
  defp apply_method(conn, :put, path), do: put(conn, path, %{})
  defp apply_method(conn, :delete, path), do: delete(conn, path)
end
