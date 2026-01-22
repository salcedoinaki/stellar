defmodule StellarWeb.Auth.ErrorHandler do
  @moduledoc """
  Error handler for Guardian authentication failures.
  """

  import Plug.Conn
  use Phoenix.Controller, formats: [:json]

  @behaviour Guardian.Plug.ErrorHandler

  @impl Guardian.Plug.ErrorHandler
  def auth_error(conn, {type, reason}, _opts) do
    {status, message} = error_response(type, reason)

    conn
    |> put_status(status)
    |> put_view(StellarWeb.ErrorJSON)
    |> render("error.json", %{message: message, type: type})
  end

  defp error_response(:unauthenticated, _reason) do
    {401, "Authentication required"}
  end

  defp error_response(:invalid_token, _reason) do
    {401, "Invalid or expired token"}
  end

  defp error_response(:no_resource_found, _reason) do
    {401, "User not found"}
  end

  defp error_response(:token_expired, _reason) do
    {401, "Token has expired"}
  end

  defp error_response(:already_authenticated, _reason) do
    {400, "Already authenticated"}
  end

  defp error_response(_type, _reason) do
    {401, "Authentication failed"}
  end
end
