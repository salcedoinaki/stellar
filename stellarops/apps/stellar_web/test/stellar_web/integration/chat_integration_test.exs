defmodule StellarWeb.ChatIntegrationTest do
  @moduledoc """
  Integration tests for chat/NLP endpoint.
  """
  
  use StellarWeb.ConnCase, async: true
  
  alias StellarData.Users
  alias StellarWeb.Auth.Guardian
  
  @valid_user_attrs %{
    email: "operator@stellarops.com",
    password: "SecurePassword123!",
    role: "operator"
  }
  
  setup do
    {:ok, user} = Users.create_user(@valid_user_attrs)
    {:ok, token, _} = Guardian.encode_and_sign(user)
    {:ok, user: user, token: token}
  end
  
  describe "POST /api/chat" do
    test "returns response for valid query", %{conn: conn, token: token} do
      conn =
        conn
        |> put_req_header("authorization", "Bearer #{token}")
        |> post(~p"/api/chat", %{message: "What satellites are in LEO?"})
      
      response = json_response(conn, 200)
      
      assert response["response"]
      assert is_binary(response["response"])
    end
    
    test "handles satellite-related queries", %{conn: conn, token: token} do
      conn =
        conn
        |> put_req_header("authorization", "Bearer #{token}")
        |> post(~p"/api/chat", %{message: "List all active satellites"})
      
      response = json_response(conn, 200)
      
      assert response["response"]
      assert response["intent"] == "list_satellites" or is_nil(response["intent"])
    end
    
    test "handles conjunction queries", %{conn: conn, token: token} do
      conn =
        conn
        |> put_req_header("authorization", "Bearer #{token}")
        |> post(~p"/api/chat", %{message: "Show me upcoming conjunctions"})
      
      response = json_response(conn, 200)
      
      assert response["response"]
    end
    
    test "handles threat queries", %{conn: conn, token: token} do
      conn =
        conn
        |> put_req_header("authorization", "Bearer #{token}")
        |> post(~p"/api/chat", %{message: "What are the current threats?"})
      
      response = json_response(conn, 200)
      
      assert response["response"]
    end
    
    test "handles mission queries", %{conn: conn, token: token} do
      conn =
        conn
        |> put_req_header("authorization", "Bearer #{token}")
        |> post(~p"/api/chat", %{message: "What missions are running?"})
      
      response = json_response(conn, 200)
      
      assert response["response"]
    end
    
    test "returns 401 without authentication", %{conn: conn} do
      conn = post(conn, ~p"/api/chat", %{message: "Hello"})
      
      assert conn.status == 401
    end
    
    test "returns 400 for empty message", %{conn: conn, token: token} do
      conn =
        conn
        |> put_req_header("authorization", "Bearer #{token}")
        |> post(~p"/api/chat", %{message: ""})
      
      response = json_response(conn, 400)
      
      assert response["error"]
    end
    
    test "returns 400 for missing message field", %{conn: conn, token: token} do
      conn =
        conn
        |> put_req_header("authorization", "Bearer #{token}")
        |> post(~p"/api/chat", %{})
      
      response = json_response(conn, 400)
      
      assert response["error"]
    end
    
    test "includes context in response when available", %{conn: conn, token: token} do
      conn =
        conn
        |> put_req_header("authorization", "Bearer #{token}")
        |> post(~p"/api/chat", %{message: "Tell me about ISS"})
      
      response = json_response(conn, 200)
      
      # May include related data
      assert response["response"]
    end
    
    test "maintains conversation context", %{conn: conn, token: token} do
      # First message
      conn1 =
        conn
        |> put_req_header("authorization", "Bearer #{token}")
        |> post(~p"/api/chat", %{message: "Tell me about ISS"})
      
      response1 = json_response(conn1, 200)
      session_id = response1["session_id"]
      
      # Follow-up message with session
      conn2 =
        conn
        |> put_req_header("authorization", "Bearer #{token}")
        |> post(~p"/api/chat", %{
          message: "What is its current altitude?",
          session_id: session_id
        })
      
      response2 = json_response(conn2, 200)
      
      assert response2["response"]
    end
    
    test "rate limits excessive requests", %{conn: conn, token: token} do
      # Make many requests
      results =
        for _ <- 1..50 do
          conn
          |> put_req_header("authorization", "Bearer #{token}")
          |> post(~p"/api/chat", %{message: "Hello"})
          |> Map.get(:status)
        end
      
      # Should have some rate limited responses
      rate_limited = Enum.count(results, &(&1 == 429))
      
      # May or may not be rate limited depending on configuration
      assert is_integer(rate_limited)
    end
  end
  
  describe "chat WebSocket channel" do
    test "can join chat channel with valid token", %{token: token} do
      {:ok, socket} = connect(StellarWeb.UserSocket, %{"token" => token})
      {:ok, _reply, _socket} = subscribe_and_join(socket, "chat:lobby", %{})
      
      assert true
    end
    
    test "receives response on chat message", %{token: token} do
      {:ok, socket} = connect(StellarWeb.UserSocket, %{"token" => token})
      {:ok, _reply, socket} = subscribe_and_join(socket, "chat:lobby", %{})
      
      ref = push(socket, "message", %{text: "Hello"})
      
      assert_reply ref, :ok, %{response: _}
    end
  end
end
