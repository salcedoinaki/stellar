defmodule StellarWeb.AuthController do
  @moduledoc """
  Authentication controller for login, logout, and token management.
  """

  use Phoenix.Controller, formats: [:json]
  alias StellarData.Users
  alias StellarWeb.Auth.Guardian

  action_fallback StellarWeb.FallbackController

  @doc """
  POST /api/auth/login

  Authenticates a user and returns a JWT token.

  ## Request Body
  ```json
  {
    "email": "user@example.com",
    "password": "password123"
  }
  ```

  ## Response
  ```json
  {
    "token": "eyJ...",
    "user": {
      "id": "uuid",
      "email": "user@example.com",
      "name": "John Doe",
      "role": "operator"
    }
  }
  ```
  """
  def login(conn, %{"email" => email, "password" => password}) do
    case Users.authenticate(email, password) do
      {:ok, user} ->
        {:ok, token, _claims} = Guardian.encode_and_sign(user, %{}, ttl: {12, :hour})

        conn
        |> put_status(:ok)
        |> json(%{
          token: token,
          user: serialize_user(user),
          expires_in: 12 * 3600
        })

      {:error, :invalid_credentials} ->
        conn
        |> put_status(:unauthorized)
        |> json(%{error: "Invalid email or password"})

      {:error, :account_disabled} ->
        conn
        |> put_status(:forbidden)
        |> json(%{error: "Account is disabled"})

      {:error, :account_locked} ->
        conn
        |> put_status(:forbidden)
        |> json(%{error: "Account is locked due to too many failed login attempts"})
    end
  end

  def login(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "Email and password are required"})
  end

  @doc """
  POST /api/auth/logout

  Revokes the current token.
  """
  def logout(conn, _params) do
    case Guardian.Plug.current_token(conn) do
      nil ->
        conn
        |> put_status(:ok)
        |> json(%{message: "Logged out"})

      token ->
        Guardian.revoke(token)
        
        conn
        |> Guardian.Plug.sign_out()
        |> put_status(:ok)
        |> json(%{message: "Logged out successfully"})
    end
  end

  @doc """
  POST /api/auth/refresh

  Refreshes the current token.
  """
  def refresh(conn, _params) do
    case Guardian.Plug.current_token(conn) do
      nil ->
        conn
        |> put_status(:unauthorized)
        |> json(%{error: "No token provided"})

      old_token ->
        case Guardian.refresh(old_token, ttl: {12, :hour}) do
          {:ok, _old_claims, {new_token, _new_claims}} ->
            conn
            |> put_status(:ok)
            |> json(%{
              token: new_token,
              expires_in: 12 * 3600
            })

          {:error, reason} ->
            conn
            |> put_status(:unauthorized)
            |> json(%{error: "Failed to refresh token: #{inspect(reason)}"})
        end
    end
  end

  @doc """
  GET /api/auth/me

  Returns the current authenticated user.
  """
  def me(conn, _params) do
    case Guardian.Plug.current_resource(conn) do
      nil ->
        conn
        |> put_status(:unauthorized)
        |> json(%{error: "Not authenticated"})

      user ->
        conn
        |> put_status(:ok)
        |> json(%{user: serialize_user(user)})
    end
  end

  @doc """
  POST /api/auth/change-password

  Changes the current user's password.
  """
  def change_password(conn, %{"current_password" => current, "new_password" => new}) do
    user = Guardian.Plug.current_resource(conn)

    if StellarData.Users.User.valid_password?(user, current) do
      case Users.update_user_password(user, %{password: new}) do
        {:ok, _user} ->
          # Revoke current token to force re-login
          Guardian.revoke(Guardian.Plug.current_token(conn))

          conn
          |> put_status(:ok)
          |> json(%{message: "Password changed successfully. Please log in again."})

        {:error, changeset} ->
          errors = format_changeset_errors(changeset)
          
          conn
          |> put_status(:unprocessable_entity)
          |> json(%{error: "Failed to change password", details: errors})
      end
    else
      conn
      |> put_status(:unauthorized)
      |> json(%{error: "Current password is incorrect"})
    end
  end

  def change_password(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "current_password and new_password are required"})
  end

  # ============================================================================
  # Private Helpers
  # ============================================================================

  defp serialize_user(user) do
    %{
      id: user.id,
      email: user.email,
      name: user.name,
      role: user.role,
      last_login_at: user.last_login_at
    }
  end

  defp format_changeset_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
  end
end
