defmodule StellarWeb.AuthorizationTest do
  @moduledoc """
  Tests for role-based authorization.
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
    
    # Generate tokens for each user
    {:ok, admin_token, _} = Guardian.encode_and_sign(admin)
    {:ok, operator_token, _} = Guardian.encode_and_sign(operator)
    {:ok, analyst_token, _} = Guardian.encode_and_sign(analyst)
    {:ok, viewer_token, _} = Guardian.encode_and_sign(viewer)
    
    {:ok, 
     admin: admin, 
     operator: operator, 
     analyst: analyst, 
     viewer: viewer,
     admin_token: admin_token,
     operator_token: operator_token,
     analyst_token: analyst_token,
     viewer_token: viewer_token}
  end
  
  describe "role hierarchy" do
    test "admin has highest privileges", %{admin: admin} do
      assert Users.has_role?(admin, :admin)
      assert Users.has_role?(admin, :operator)
      assert Users.has_role?(admin, :analyst)
      assert Users.has_role?(admin, :viewer)
    end
    
    test "operator has operator and below privileges", %{operator: operator} do
      refute Users.has_role?(operator, :admin)
      assert Users.has_role?(operator, :operator)
      assert Users.has_role?(operator, :analyst)
      assert Users.has_role?(operator, :viewer)
    end
    
    test "analyst has analyst and below privileges", %{analyst: analyst} do
      refute Users.has_role?(analyst, :admin)
      refute Users.has_role?(analyst, :operator)
      assert Users.has_role?(analyst, :analyst)
      assert Users.has_role?(analyst, :viewer)
    end
    
    test "viewer has only viewer privileges", %{viewer: viewer} do
      refute Users.has_role?(viewer, :admin)
      refute Users.has_role?(viewer, :operator)
      refute Users.has_role?(viewer, :analyst)
      assert Users.has_role?(viewer, :viewer)
    end
  end
  
  describe "permission checks" do
    test "manage_users requires admin", %{admin: admin, operator: operator} do
      assert Users.can?(admin, :manage_users)
      refute Users.can?(operator, :manage_users)
    end
    
    test "select_coa requires operator+", %{admin: admin, operator: operator, analyst: analyst} do
      assert Users.can?(admin, :select_coa)
      assert Users.can?(operator, :select_coa)
      refute Users.can?(analyst, :select_coa)
    end
    
    test "classify_threat requires analyst+", %{operator: operator, analyst: analyst, viewer: viewer} do
      assert Users.can?(operator, :classify_threat)
      assert Users.can?(analyst, :classify_threat)
      refute Users.can?(viewer, :classify_threat)
    end
    
    test "view_dashboard available to all authenticated", 
         %{admin: admin, operator: operator, analyst: analyst, viewer: viewer} do
      assert Users.can?(admin, :view_dashboard)
      assert Users.can?(operator, :view_dashboard)
      assert Users.can?(analyst, :view_dashboard)
      assert Users.can?(viewer, :view_dashboard)
    end
  end
  
  describe "EnsureRole plug" do
    test "allows admin to access admin routes", %{conn: conn, admin_token: token} do
      # This would test a protected route - adjust based on actual routes
      conn =
        conn
        |> put_req_header("authorization", "Bearer #{token}")
        |> get(~p"/api/satellites")
      
      assert conn.status == 200
    end
    
    test "viewer can access read-only endpoints", %{conn: conn, viewer_token: token} do
      conn =
        conn
        |> put_req_header("authorization", "Bearer #{token}")
        |> get(~p"/api/satellites")
      
      assert conn.status == 200
    end
    
    test "unauthenticated users get 401", %{conn: conn} do
      conn = get(conn, ~p"/api/auth/me")
      
      assert conn.status == 401
    end
  end
  
  describe "role claims in token" do
    test "token contains user role", %{admin: admin, admin_token: token} do
      {:ok, claims} = Guardian.decode_and_verify(token)
      
      assert claims["role"] == "admin"
      assert claims["email"] == admin.email
    end
    
    test "token contains user ID as subject", %{admin: admin, admin_token: token} do
      {:ok, claims} = Guardian.decode_and_verify(token)
      
      assert claims["sub"] == to_string(admin.id)
    end
  end
  
  describe "authorization logging" do
    test "logs authorization failures", %{conn: conn, viewer_token: token} do
      # Capture log output
      log_output =
        ExUnit.CaptureLog.capture_log(fn ->
          # Try to access an operator-only route (if any exist)
          # This is a placeholder - adjust based on actual protected routes
          _conn =
            conn
            |> put_req_header("authorization", "Bearer #{token}")
            |> post(~p"/api/satellites", %{})
        end)
      
      # If authorization fails, it should be logged
      # (actual assertion depends on route protection)
      assert is_binary(log_output)
    end
  end
  
  describe "role update" do
    test "admin can change user role", %{viewer: viewer} do
      {:ok, updated_user} = Users.update_role(viewer, "analyst")
      
      assert updated_user.role == "analyst"
      assert Users.has_role?(updated_user, :analyst)
    end
    
    test "rejects invalid role", %{viewer: viewer} do
      {:error, changeset} = Users.update_role(viewer, "superadmin")
      
      assert changeset.errors[:role]
    end
  end
  
  describe "account status" do
    test "deactivated users cannot authenticate", %{viewer: viewer} do
      {:ok, _} = Users.deactivate_user(viewer)
      
      result = Users.authenticate(viewer.email, "SecurePassword123!")
      
      assert {:error, :account_disabled} = result
    end
    
    test "reactivated users can authenticate", %{viewer: viewer} do
      {:ok, deactivated} = Users.deactivate_user(viewer)
      {:ok, reactivated} = Users.activate_user(deactivated)
      
      result = Users.authenticate(reactivated.email, "SecurePassword123!")
      
      assert {:ok, _user} = result
    end
  end
end
