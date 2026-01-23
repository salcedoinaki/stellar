defmodule StellarWeb.AuthorizationTest do
  @moduledoc """
  Tests for role-based authorization across all protected endpoints.
  """
  use StellarWeb.ConnCase, async: true
  
  alias StellarData.Users
  alias StellarWeb.Auth.Guardian
  
  setup do
    users = %{
      admin: create_user(:admin),
      operator: create_user(:operator),
      analyst: create_user(:analyst),
      viewer: create_user(:viewer)
    }
    
    {:ok, users: users}
  end
  
  defp create_user(role) do
    {:ok, user} = Users.create_user(%{
      email: "#{role}@stellarops.com",
      password: "SecurePassword123!",
      role: role
    })
    user
  end
  
  defp auth_conn(conn, user) do
    {:ok, token, _claims} = Guardian.encode_and_sign(user)
    put_req_header(conn, "authorization", "Bearer #{token}")
  end
  
  describe "satellite endpoints" do
    test "viewer can read satellites", %{conn: conn, users: users} do
      conn = conn
        |> auth_conn(users.viewer)
        |> get(~p"/api/satellites")
      
      assert conn.status == 200
    end
    
    test "viewer cannot create satellites", %{conn: conn, users: users} do
      conn = conn
        |> auth_conn(users.viewer)
        |> post(~p"/api/satellites", %{name: "SAT-001"})
      
      assert conn.status == 403
    end
    
    test "operator can create satellites", %{conn: conn, users: users} do
      conn = conn
        |> auth_conn(users.operator)
        |> post(~p"/api/satellites", %{name: "SAT-001", norad_id: 99999})
      
      assert conn.status in [200, 201]
    end
  end
  
  describe "mission endpoints" do
    test "viewer cannot create missions", %{conn: conn, users: users} do
      conn = conn
        |> auth_conn(users.viewer)
        |> post(~p"/api/missions", %{name: "Test Mission"})
      
      assert conn.status == 403
    end
    
    test "analyst cannot create missions", %{conn: conn, users: users} do
      conn = conn
        |> auth_conn(users.analyst)
        |> post(~p"/api/missions", %{name: "Test Mission"})
      
      assert conn.status == 403
    end
    
    test "operator can create missions", %{conn: conn, users: users} do
      conn = conn
        |> auth_conn(users.operator)
        |> post(~p"/api/missions", %{
          name: "Test Mission",
          type: "observation",
          satellite_id: Ecto.UUID.generate()
        })
      
      # May be 422 due to validation, but not 403
      refute conn.status == 403
    end
    
    test "admin can create missions", %{conn: conn, users: users} do
      conn = conn
        |> auth_conn(users.admin)
        |> post(~p"/api/missions", %{
          name: "Test Mission",
          type: "observation",
          satellite_id: Ecto.UUID.generate()
        })
      
      refute conn.status == 403
    end
  end
  
  describe "COA endpoints" do
    test "viewer cannot select COA", %{conn: conn, users: users} do
      coa_id = Ecto.UUID.generate()
      
      conn = conn
        |> auth_conn(users.viewer)
        |> post(~p"/api/coas/#{coa_id}/select")
      
      assert conn.status == 403
    end
    
    test "analyst cannot select COA", %{conn: conn, users: users} do
      coa_id = Ecto.UUID.generate()
      
      conn = conn
        |> auth_conn(users.analyst)
        |> post(~p"/api/coas/#{coa_id}/select")
      
      assert conn.status == 403
    end
    
    test "operator can select COA", %{conn: conn, users: users} do
      coa_id = Ecto.UUID.generate()
      
      conn = conn
        |> auth_conn(users.operator)
        |> post(~p"/api/coas/#{coa_id}/select")
      
      # May be 404 (not found), but not 403
      refute conn.status == 403
    end
  end
  
  describe "threat classification endpoints" do
    test "viewer cannot classify threats", %{conn: conn, users: users} do
      conn = conn
        |> auth_conn(users.viewer)
        |> post(~p"/api/objects/25544/classify", %{classification: "hostile"})
      
      assert conn.status == 403
    end
    
    test "operator cannot classify threats", %{conn: conn, users: users} do
      conn = conn
        |> auth_conn(users.operator)
        |> post(~p"/api/objects/25544/classify", %{classification: "hostile"})
      
      assert conn.status == 403
    end
    
    test "analyst can classify threats", %{conn: conn, users: users} do
      conn = conn
        |> auth_conn(users.analyst)
        |> post(~p"/api/objects/25544/classify", %{classification: "hostile"})
      
      # May be 404 (not found), but not 403
      refute conn.status == 403
    end
  end
  
  describe "user management endpoints" do
    test "viewer cannot manage users", %{conn: conn, users: users} do
      conn = conn
        |> auth_conn(users.viewer)
        |> get(~p"/api/admin/users")
      
      assert conn.status == 403
    end
    
    test "operator cannot manage users", %{conn: conn, users: users} do
      conn = conn
        |> auth_conn(users.operator)
        |> get(~p"/api/admin/users")
      
      assert conn.status == 403
    end
    
    test "analyst cannot manage users", %{conn: conn, users: users} do
      conn = conn
        |> auth_conn(users.analyst)
        |> get(~p"/api/admin/users")
      
      assert conn.status == 403
    end
    
    test "admin can manage users", %{conn: conn, users: users} do
      conn = conn
        |> auth_conn(users.admin)
        |> get(~p"/api/admin/users")
      
      assert conn.status == 200
    end
    
    test "admin can create users", %{conn: conn, users: users} do
      conn = conn
        |> auth_conn(users.admin)
        |> post(~p"/api/admin/users", %{
          email: "newuser@stellarops.com",
          password: "SecurePassword123!",
          role: "viewer"
        })
      
      assert conn.status in [200, 201]
    end
    
    test "admin can delete users", %{conn: conn, users: users} do
      {:ok, target_user} = Users.create_user(%{
        email: "delete-me@stellarops.com",
        password: "password",
        role: :viewer
      })
      
      conn = conn
        |> auth_conn(users.admin)
        |> delete(~p"/api/admin/users/#{target_user.id}")
      
      assert conn.status in [200, 204]
    end
  end
  
  describe "authorization logging" do
    test "failed authorization attempts are logged", %{conn: conn, users: users} do
      # Capture log output
      log = ExUnit.CaptureLog.capture_log(fn ->
        conn
        |> auth_conn(users.viewer)
        |> post(~p"/api/missions", %{name: "Test"})
      end)
      
      assert log =~ "authorization" or log =~ "forbidden" or log =~ "denied"
    end
  end
end
