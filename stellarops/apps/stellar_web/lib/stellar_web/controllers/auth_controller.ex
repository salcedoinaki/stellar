defmodule StellarWeb.AuthController do
  @moduledoc """
  Authentication controller for login, logout, and token refresh.
  """
  
  use StellarWeb, :controller
  
  alias StellarData.Users
  alias StellarWeb.Auth.Guardian
  alias StellarWeb.Auth.TokenRevocation
  
  require Logger
  
  action_fallback StellarWeb.FallbackController
  
  @doc """
  Login endpoint - authenticates user and returns JWT tokens.
  
  POST /api/auth/login
  Body: {"email": "...", "password": "..."}
  """
  def login(conn, %{"email" => email, "password" => password}) do
    with {:ok, user} <- Users.authenticate(email, password),
         {:ok, access_token, _claims} <- Guardian.encode_and_sign(user, %{}, token_type: "access", ttl: {1, :hour}),
         {:ok, refresh_token, _claims} <- Guardian.encode_and_sign(user, %{}, token_type: "refresh", ttl: {7, :day}) do
      
      Logger.info("User logged in", user_id: user.id, email: user.email)
      
      conn
      |> put_status(:ok)
      |> render(:tokens, %{
        access_token: access_token,
        refresh_token: refresh_token,
        user: user,
        expires_in: 3600
      })
    else
      {:error, :invalid_credentials} ->
        Logger.warning("Failed login attempt", email: email, remote_ip: remote_ip(conn))
        
        conn
        |> put_status(:unauthorized)
        |> put_view(json: StellarWeb.ErrorJSON)
        |> render(:error, %{message: "Invalid email or password"})
      
      {:error, :user_not_found} ->
        # Same response to prevent user enumeration
        Logger.warning("Login attempt for unknown user", email: email, remote_ip: remote_ip(conn))
        
        conn
        |> put_status(:unauthorized)
        |> put_view(json: StellarWeb.ErrorJSON)
        |> render(:error, %{message: "Invalid email or password"})
      
      {:error, :account_disabled} ->
        Logger.warning("Login attempt for disabled account", email: email, remote_ip: remote_ip(conn))
        
        conn
        |> put_status(:forbidden)
        |> put_view(json: StellarWeb.ErrorJSON)
        |> render(:error, %{message: "Account is disabled"})
      
      {:error, :account_locked} ->
        Logger.warning("Login attempt for locked account", email: email, remote_ip: remote_ip(conn))
        
        conn
        |> put_status(:forbidden)
        |> put_view(json: StellarWeb.ErrorJSON)
        |> render(:error, %{message: "Account is locked due to too many failed login attempts"})
    end
  end
  
  def login(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> put_view(json: StellarWeb.ErrorJSON)
    |> render(:error, %{message: "Email and password are required"})
  end
  
  @doc """
  Refresh endpoint - exchanges refresh token for new access token.
  
  POST /api/auth/refresh
  Body: {"refresh_token": "..."}
  """
  def refresh(conn, %{"refresh_token" => refresh_token}) do
    case Guardian.decode_and_verify(refresh_token, %{typ: "refresh"}) do
      {:ok, claims} ->
        case Guardian.resource_from_claims(claims) do
          {:ok, user} ->
            # Revoke old refresh token and issue new tokens
            Guardian.revoke_token(refresh_token)
            
            {:ok, new_access_token, _} = Guardian.encode_and_sign(user, %{}, token_type: "access", ttl: {1, :hour})
            {:ok, new_refresh_token, _} = Guardian.encode_and_sign(user, %{}, token_type: "refresh", ttl: {7, :day})
            
            Logger.info("Token refreshed", user_id: user.id)
            
            conn
            |> put_status(:ok)
            |> render(:tokens, %{
              access_token: new_access_token,
              refresh_token: new_refresh_token,
              user: user,
              expires_in: 3600
            })
          
          {:error, reason} ->
            Logger.warning("Refresh failed - invalid user", reason: reason)
            
            conn
            |> put_status(:unauthorized)
            |> put_view(json: StellarWeb.ErrorJSON)
            |> render(:error, %{message: "Invalid refresh token"})
        end
      
      {:error, reason} ->
        Logger.warning("Refresh failed - invalid token", reason: inspect(reason))
        
        conn
        |> put_status(:unauthorized)
        |> put_view(json: StellarWeb.ErrorJSON)
        |> render(:error, %{message: "Invalid or expired refresh token"})
    end
  end
  
  def refresh(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> put_view(json: StellarWeb.ErrorJSON)
    |> render(:error, %{message: "Refresh token is required"})
  end
  
  @doc """
  Logout endpoint - revokes current token.
  
  POST /api/auth/logout
  Authorization: Bearer <token>
  """
  def logout(conn, _params) do
    token = Guardian.Plug.current_token(conn)
    user = Guardian.Plug.current_resource(conn)
    
    if token do
      Guardian.revoke_token(token)
      Logger.info("User logged out", user_id: user && user.id)
    end
    
    conn
    |> put_status(:ok)
    |> json(%{message: "Logged out successfully"})
  end
  
  @doc """
  Logout all - revokes all tokens for the current user.
  
  POST /api/auth/logout_all
  Authorization: Bearer <token>
  """
  def logout_all(conn, _params) do
    user = Guardian.Plug.current_resource(conn)
    
    if user do
      TokenRevocation.revoke_all_for_user(user.id)
      Logger.info("All tokens revoked for user", user_id: user.id)
    end
    
    conn
    |> put_status(:ok)
    |> json(%{message: "All sessions terminated"})
  end
  
  @doc """
  Get current user info.
  
  GET /api/auth/me
  Authorization: Bearer <token>
  """
  def me(conn, _params) do
    user = Guardian.Plug.current_resource(conn)
    
    conn
    |> put_status(:ok)
    |> render(:user, %{user: user})
  end
  
  @doc """
  Change password for current user.
  
  POST /api/auth/change_password
  Authorization: Bearer <token>
  Body: {"current_password": "...", "new_password": "..."}
  """
  def change_password(conn, %{"current_password" => current, "new_password" => new_password}) do
    user = Guardian.Plug.current_resource(conn)
    
    with {:ok, _user} <- Users.verify_password(user, current),
         {:ok, _user} <- Users.update_password(user, new_password) do
      
      # Revoke all existing tokens to force re-login
      TokenRevocation.revoke_all_for_user(user.id)
      
      Logger.info("Password changed", user_id: user.id)
      
      conn
      |> put_status(:ok)
      |> json(%{message: "Password changed successfully. Please log in again."})
    else
      {:error, :invalid_password} ->
        conn
        |> put_status(:unauthorized)
        |> put_view(json: StellarWeb.ErrorJSON)
        |> render(:error, %{message: "Current password is incorrect"})
      
      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> put_view(json: StellarWeb.ChangesetJSON)
        |> render(:error, changeset: changeset)
    end
  end
  
  def change_password(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> put_view(json: StellarWeb.ErrorJSON)
    |> render(:error, %{message: "Current password and new password are required"})
  end
  
  # Private helpers
  
  defp remote_ip(conn) do
    conn.remote_ip |> :inet.ntoa() |> to_string()
  end
end
