defmodule StellarWeb.Auth.Guardian do
  @moduledoc """
  Guardian implementation for JWT authentication.
  
  Handles JWT token generation and validation for the StellarOps API.
  """

  use Guardian, otp_app: :stellar_web

  alias StellarData.Users

  @doc """
  Identifies the subject of the token (the user ID).
  """
  def subject_for_token(%{id: id}, _claims) do
    {:ok, to_string(id)}
  end

  def subject_for_token(_, _) do
    {:error, :invalid_resource}
  end

  @doc """
  Retrieves the user from the token subject.
  """
  def resource_from_claims(%{"sub" => id}) do
    case Users.get_user(id) do
      nil -> {:error, :user_not_found}
      user -> {:ok, user}
    end
  end

  def resource_from_claims(_) do
    {:error, :invalid_claims}
  end

  @doc """
  Adds custom claims to the token.
  """
  def build_claims(claims, resource, opts) do
    claims =
      claims
      |> Map.put("role", to_string(resource.role))
      |> Map.put("email", resource.email)
      |> Map.put("name", resource.name)

    {:ok, claims}
  end

  @doc """
  Called after a token is created.
  """
  def after_encode_and_sign(resource, claims, token, _opts) do
    {:ok, token}
  end

  @doc """
  Called after a token is verified.
  """
  def on_verify(claims, token, _opts) do
    # Could add additional verification here (e.g., check if user still active)
    {:ok, claims}
  end

  @doc """
  Called on token refresh.
  """
  def on_refresh({old_token, old_claims}, {new_token, new_claims}, _opts) do
    {:ok, {old_token, old_claims}, {new_token, new_claims}}
  end

  @doc """
  Called on token revocation.
  """
  def on_revoke(claims, token, _opts) do
    # Could add token to a blocklist here
    {:ok, claims}
  end
end
