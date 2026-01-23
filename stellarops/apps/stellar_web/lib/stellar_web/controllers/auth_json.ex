defmodule StellarWeb.AuthJSON do
  @moduledoc """
  JSON rendering for authentication responses.
  """
  
  def tokens(%{access_token: access_token, refresh_token: refresh_token, user: user, expires_in: expires_in}) do
    %{
      access_token: access_token,
      refresh_token: refresh_token,
      token_type: "Bearer",
      expires_in: expires_in,
      user: user_data(user)
    }
  end
  
  def user(%{user: user}) do
    %{user: user_data(user)}
  end
  
  defp user_data(user) do
    %{
      id: user.id,
      email: user.email,
      role: user.role,
      inserted_at: user.inserted_at
    }
  end
end
