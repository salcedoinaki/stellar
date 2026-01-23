defmodule StellarWeb.UserSocket do
  @moduledoc """
  WebSocket connection handler for StellarOps.
  
  Supports token-based authentication for secure connections.
  
  ## Authentication (TASK-127)
  
  Clients should connect with a JWT token:
  ```javascript
  let socket = new Socket("/socket", {params: {token: userToken}})
  ```
  
  For development/testing, connections without tokens are allowed
  when `allow_anonymous: true` is set in config.
  """

  use Phoenix.Socket

  channel "satellites:*", StellarWeb.SatelliteChannel
  channel "missions:*", StellarWeb.MissionChannel
  channel "alarms:*", StellarWeb.AlarmChannel
  channel "ssa:*", StellarWeb.SSAChannel

  @impl true
  def connect(params, socket, _connect_info) do
    case authenticate(params) do
      {:ok, user_id} ->
        socket = assign(socket, :user_id, user_id)
        {:ok, socket}

      :anonymous ->
        # Allow anonymous connections in development
        if allow_anonymous?() do
          socket = assign(socket, :user_id, nil)
          {:ok, socket}
        else
          :error
        end

      :error ->
        :error
    end
  end

  @impl true
  def id(socket) do
    case socket.assigns[:user_id] do
      nil -> nil
      user_id -> "user_socket:#{user_id}"
    end
  end

  # ============================================================================
  # Authentication Helpers
  # ============================================================================

  defp authenticate(%{"token" => "guest-token"}), do: :anonymous

  defp authenticate(%{"token" => token}) when is_binary(token) and token != "" do
    # Try to verify the JWT token
    case verify_token(token) do
      {:ok, user_id} -> {:ok, user_id}
      :error -> :error
    end
  end

  defp authenticate(_params), do: :anonymous

  defp verify_token(token) do
    # Check if Guardian is configured
    if Code.ensure_loaded?(StellarWeb.Auth.Guardian) do
      case StellarWeb.Auth.Guardian.decode_and_verify(token) do
        {:ok, claims} ->
          {:ok, claims["sub"]}

        {:error, _reason} ->
          :error
      end
    else
      # Guardian not configured, use simple token validation for development
      # In production, this should always verify against Guardian
      validate_simple_token(token)
    end
  end

  # Simple token validation for development/testing
  # Format: "user:USER_ID:SECRET"
  defp validate_simple_token(token) do
    case String.split(token, ":") do
      ["user", user_id, _secret] when user_id != "" ->
        {:ok, user_id}

      _ ->
        :error
    end
  end

  defp allow_anonymous? do
    Application.get_env(:stellar_web, :allow_anonymous_websocket, Mix.env() == :dev)
  end
end
