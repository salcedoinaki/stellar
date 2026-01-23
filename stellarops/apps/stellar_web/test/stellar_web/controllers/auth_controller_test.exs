defmodule StellarWeb.AuthControllerTest do
  @moduledoc """
  Tests for authentication flow including login, logout, token refresh, and revocation.
  """
  use StellarWeb.ConnCase, async: true
  
  alias StellarData.Users
  alias StellarWeb.Auth.Guardian
  
  @valid_user_attrs %{
    email: "test@stellarops.com",
    password: "SecurePassword123!",
    role: :operator
  }
  
  setup do
    {:ok, user} = Users.create_user(@valid_user_attrs)
    {:ok, user: user}
  end
  
  describe "POST /api/auth/login" do
    test "returns token with valid credentials", %{conn: conn, user: user} do
      conn = post(conn, ~p"/api/auth/login", %{
        email: user.email,
        password: "SecurePassword123!"
      })
      
      assert %{"token" => token, "user" => user_data} = json_response(conn, 200)
      assert token != nil
      assert user_data["email"] == user.email
      assert user_data["role"] == "operator"
      
      # Verify token is valid
      {:ok, claims} = Guardian.decode_and_verify(token)
      assert claims["sub"] == user.id
    end
    
    test "returns 401 with invalid password", %{conn: conn, user: user} do
      conn = post(conn, ~p"/api/auth/login", %{
        email: user.email,
        password: "WrongPassword"
      })
      
      assert %{"error" => "invalid_credentials"} = json_response(conn, 401)
    end
    
    test "returns 401 with non-existent email", %{conn: conn} do
      conn = post(conn, ~p"/api/auth/login", %{
        email: "nonexistent@stellarops.com",
        password: "password"
      })
      
      assert %{"error" => "invalid_credentials"} = json_response(conn, 401)
    end
    
    test "returns 422 with missing fields", %{conn: conn} do
      conn = post(conn, ~p"/api/auth/login", %{})
      
      assert %{"error" => _} = json_response(conn, 422)
    end
    
    test "rate limits excessive login attempts", %{conn: conn, user: user} do
      # Make 10 failed attempts
      for _ <- 1..10 do
        post(conn, ~p"/api/auth/login", %{
          email: user.email,
          password: "WrongPassword"
        })
      end
      
      # 11th attempt should be rate limited
      conn = post(conn, ~p"/api/auth/login", %{
        email: user.email,
        password: "WrongPassword"
      })
      
      assert conn.status == 429
      assert get_resp_header(conn, "retry-after") != []
    end
  end
  
  describe "POST /api/auth/refresh" do
    test "returns new token with valid refresh token", %{conn: conn, user: user} do
      {:ok, token, _claims} = Guardian.encode_and_sign(user, %{}, token_type: "refresh")
      
      conn = conn
        |> put_req_header("authorization", "Bearer #{token}")
        |> post(~p"/api/auth/refresh")
      
      assert %{"token" => new_token} = json_response(conn, 200)
      assert new_token != token
    end
    
    test "returns 401 with expired token", %{conn: conn, user: user} do
      # Create token that expired 1 hour ago
      {:ok, token, _claims} = Guardian.encode_and_sign(user, %{}, 
        token_type: "refresh",
        ttl: {-1, :hour}
      )
      
      conn = conn
        |> put_req_header("authorization", "Bearer #{token}")
        |> post(~p"/api/auth/refresh")
      
      assert conn.status == 401
    end
    
    test "returns 401 with revoked token", %{conn: conn, user: user} do
      {:ok, token, claims} = Guardian.encode_and_sign(user, %{}, token_type: "refresh")
      
      # Revoke the token
      Guardian.revoke(token)
      
      conn = conn
        |> put_req_header("authorization", "Bearer #{token}")
        |> post(~p"/api/auth/refresh")
      
      assert conn.status == 401
    end
  end
  
  describe "POST /api/auth/logout" do
    test "revokes token on logout", %{conn: conn, user: user} do
      {:ok, token, _claims} = Guardian.encode_and_sign(user)
      
      conn = conn
        |> put_req_header("authorization", "Bearer #{token}")
        |> post(~p"/api/auth/logout")
      
      assert conn.status == 200
      
      # Token should now be revoked
      assert {:error, :token_revoked} = Guardian.decode_and_verify(token)
    end
    
    test "returns 401 without token", %{conn: conn} do
      conn = post(conn, ~p"/api/auth/logout")
      assert conn.status == 401
    end
  end
  
  describe "token revocation" do
    test "revoked tokens are rejected", %{conn: conn, user: user} do
      {:ok, token, _claims} = Guardian.encode_and_sign(user)
      
      # Token works initially
      conn1 = conn
        |> put_req_header("authorization", "Bearer #{token}")
        |> get(~p"/api/satellites")
      
      assert conn1.status == 200
      
      # Revoke the token
      Guardian.revoke(token)
      
      # Token should now be rejected
      conn2 = conn
        |> put_req_header("authorization", "Bearer #{token}")
        |> get(~p"/api/satellites")
      
      assert conn2.status == 401
    end
    
    test "revocation persists across processes", %{conn: conn, user: user} do
      {:ok, token, _claims} = Guardian.encode_and_sign(user)
      
      # Revoke in a different process
      Task.async(fn -> Guardian.revoke(token) end) |> Task.await()
      
      # Should still be revoked
      conn = conn
        |> put_req_header("authorization", "Bearer #{token}")
        |> get(~p"/api/satellites")
      
      assert conn.status == 401
    end
  end
end
