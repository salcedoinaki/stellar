defmodule StellarWeb.Auth.Guardian do
  @moduledoc """
  Guardian implementation for JWT authentication.
  
  Handles token generation, verification, and resource loading.
  Integrates with TokenRevocation for logout/invalidation.
  """
  
  use Guardian, otp_app: :stellar_web
  
  alias StellarData.Users
  alias StellarWeb.Auth.TokenRevocation
  
  @doc """
  Subject for token - uses user ID.
  """
  def subject_for_token(%{id: id}, _claims) do
    {:ok, to_string(id)}
  end
  
  def subject_for_token(_, _) do
    {:error, :invalid_resource}
  end
  
  @doc """
  Load user from token subject.
  """
  def resource_from_claims(%{"sub" => id} = claims) do
    case Users.get_user(id) do
      nil -> 
        {:error, :user_not_found}
      
      user ->
        # Check if token was issued before user's tokens were revoked
        case validate_token_not_revoked(user, claims) do
          :ok -> {:ok, user}
          {:error, reason} -> {:error, reason}
        end
    end
  end
  
  def resource_from_claims(_claims) do
    {:error, :invalid_claims}
  end
  
  @doc """
  Build claims for token generation.
  """
  def build_claims(claims, resource, opts) do
    claims =
      claims
      |> Map.put("role", resource.role)
      |> Map.put("email", resource.email)
      |> Map.put("jti", generate_jti())
    
    {:ok, claims}
  end
  
  @doc """
  Verify claims after token decode.
  """
  def verify_claims(claims, _opts) do
    # Check if this specific token has been revoked
    jti = Map.get(claims, "jti")
    
    if jti && TokenRevocation.revoked?(jti) do
      {:error, :token_revoked}
    else
      {:ok, claims}
    end
  end
  
  @doc """
  Called on token refresh - carry over important claims.
  """
  def on_refresh({old_token, old_claims}, {new_token, new_claims}, _opts) do
    # Revoke the old token
    if jti = Map.get(old_claims, "jti") do
      TokenRevocation.revoke(jti)
    end
    
    {:ok, {old_token, old_claims}, {new_token, new_claims}}
  end
  
  @doc """
  Revoke a token (for logout).
  """
  def revoke_token(token) do
    case decode_and_verify(token) do
      {:ok, claims} ->
        if jti = Map.get(claims, "jti") do
          exp = Map.get(claims, "exp")
          expires_at = if exp, do: DateTime.from_unix!(exp), else: nil
          TokenRevocation.revoke(jti, expires_at)
        end
        :ok
        
      {:error, reason} ->
        {:error, reason}
    end
  end
  
  @doc """
  Revoke all tokens for a user.
  """
  def revoke_all_user_tokens(user_id) do
    TokenRevocation.revoke_all_for_user(user_id)
  end
  
  # Private functions
  
  defp generate_jti do
    :crypto.strong_rand_bytes(16) |> Base.url_encode64(padding: false)
  end
  
  defp validate_token_not_revoked(user, claims) do
    iat = Map.get(claims, "iat")
    
    if iat do
      token_issued_at = DateTime.from_unix!(iat)
      
      if TokenRevocation.token_valid_for_user?(user.id, token_issued_at) do
        :ok
      else
        {:error, :token_revoked}
      end
    else
      :ok
    end
  end
end
