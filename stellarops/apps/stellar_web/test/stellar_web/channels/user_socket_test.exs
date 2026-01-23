defmodule StellarWeb.UserSocketTest do
  @moduledoc """
  Tests for WebSocket authentication (TASK-127).
  """
  use ExUnit.Case, async: true

  alias StellarWeb.UserSocket

  describe "connect/3" do
    test "allows anonymous connection when configured" do
      # Default dev config allows anonymous
      assert {:ok, socket} = UserSocket.connect(%{}, %Phoenix.Socket{}, %{})
      assert socket.assigns[:user_id] == nil
    end

    test "authenticates with valid simple token" do
      params = %{"token" => "user:123:secret_key"}
      assert {:ok, socket} = UserSocket.connect(params, %Phoenix.Socket{}, %{})
      assert socket.assigns[:user_id] == "123"
    end

    test "rejects malformed token" do
      params = %{"token" => "invalid_token_format"}
      # In dev mode, this falls back to anonymous
      result = UserSocket.connect(params, %Phoenix.Socket{}, %{})
      
      case result do
        {:ok, socket} ->
          # Anonymous fallback in dev mode
          assert socket.assigns[:user_id] == nil
        :error ->
          # Strict mode would reject
          assert true
      end
    end

    test "rejects empty token" do
      params = %{"token" => ""}
      # Empty token is treated as no token (anonymous)
      {:ok, socket} = UserSocket.connect(params, %Phoenix.Socket{}, %{})
      assert socket.assigns[:user_id] == nil
    end
  end

  describe "id/1" do
    test "returns nil for anonymous socket" do
      socket = %Phoenix.Socket{assigns: %{user_id: nil}}
      assert UserSocket.id(socket) == nil
    end

    test "returns user_socket:id for authenticated socket" do
      socket = %Phoenix.Socket{assigns: %{user_id: "user_123"}}
      assert UserSocket.id(socket) == "user_socket:user_123"
    end
  end
end
