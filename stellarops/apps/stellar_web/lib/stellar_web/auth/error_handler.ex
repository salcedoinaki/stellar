defmodule StellarWeb.Auth.ErrorHandler do
  @moduledoc """
  Error handler for Guardian authentication failures.
  """

  import Plug.Conn
  import Phoenix.Controller

  require Logger

  @behaviour Guardian.Plug.ErrorHandler

  @impl Guardian.Plug.ErrorHandler
  def auth_error(conn, {type, reason}, _opts) do
    log_auth_error(conn, type, reason)

    {status, message} = error_response(type, reason)

    conn
    |> put_status(status)
    |> put_view(json: StellarWeb.ErrorJSON)
    |> render(:error, %{message: message, type: type})
    |> halt()
  end

  defp error_response(:unauthenticated, _reason) do
    {:unauthorized, "Authentication required"}
  end

  defp error_response(:invalid_token, _reason) do
    {:unauthorized, "Invalid or expired token"}
  end

  defp error_response(:token_revoked, _reason) do
    {:unauthorized, "Token has been revoked"}
  end

  defp error_response(:no_resource_found, _reason) do
    {:unauthorized, "User not found"}
  end

  defp error_response(:token_expired, _reason) do
    {:unauthorized, "Token has expired"}
  end

  defp error_response(:already_authenticated, _reason) do
    {:bad_request, "Already authenticated"}
  end

  defp error_response(_type, _reason) do
    {:unauthorized, "Authentication failed"}
  end

  defp log_auth_error(conn, type, reason) do
    Logger.info("Authentication error",
      type: type,
      reason: inspect(reason),
      path: conn.request_path,
      method: conn.method,
      remote_ip: conn.remote_ip |> :inet.ntoa() |> to_string()
    )
  end
end
