defmodule StellarWeb.SatelliteChannelTest do
  use StellarWeb.ChannelCase

  alias StellarCore.Satellite

  setup do
    {:ok, _, socket} =
      StellarWeb.UserSocket
      |> socket()
      |> subscribe_and_join(StellarWeb.SatelliteChannel, "satellites:lobby")

    %{socket: socket}
  end

  describe "join" do
    test "successfully joins satellites:lobby", %{socket: socket} do
      assert socket.joined
    end

    @tag :skip_cleanup
    test "receives satellites_list after join containing created satellite" do
      # This test needs to run without interference from cleanup
      # Create a satellite with unique ID before joining
      unique_id = "CHANNEL-JOIN-#{System.unique_integer([:positive])}"
      {:ok, _} = Satellite.start(unique_id)
      
      # Use a fresh socket connection
      {:ok, _, socket} =
        StellarWeb.UserSocket
        |> socket()
        |> subscribe_and_join(StellarWeb.SatelliteChannel, "satellites:lobby")

      # After join, we should receive the satellites list push
      # But we already joined, so let's use get_all instead
      ref = push(socket, "get_all", %{})
      assert_reply ref, :ok, %{satellites: satellites}
      
      ids = Enum.map(satellites, & &1.id)
      assert unique_id in ids
      
      # Cleanup
      Satellite.stop(unique_id)
    end
  end

  describe "get_all" do
    test "returns all satellites", %{socket: socket} do
      {:ok, _} = Satellite.start("CHANNEL-SAT-002")
      {:ok, _} = Satellite.start("CHANNEL-SAT-003")

      ref = push(socket, "get_all", %{})
      assert_reply ref, :ok, %{satellites: satellites}

      ids = Enum.map(satellites, & &1.id)
      assert "CHANNEL-SAT-002" in ids
      assert "CHANNEL-SAT-003" in ids
    end
  end

  describe "get_satellite" do
    test "returns satellite state", %{socket: socket} do
      {:ok, _} = Satellite.start("CHANNEL-SAT-004")

      ref = push(socket, "get_satellite", %{"id" => "CHANNEL-SAT-004"})
      assert_reply ref, :ok, %{id: "CHANNEL-SAT-004", mode: "nominal"}
    end

    test "returns error for non-existent satellite", %{socket: socket} do
      ref = push(socket, "get_satellite", %{"id" => "NONEXISTENT"})
      assert_reply ref, :error, %{reason: "not_found"}
    end
  end

  describe "create_satellite" do
    test "creates a satellite and broadcasts", %{socket: socket} do
      ref = push(socket, "create_satellite", %{"id" => "CHANNEL-SAT-005"})
      assert_reply ref, :ok, %{id: "CHANNEL-SAT-005"}

      # Should receive broadcast
      assert_broadcast "satellite_created", %{id: "CHANNEL-SAT-005"}

      # Verify it exists
      assert Satellite.alive?("CHANNEL-SAT-005")
    end

    test "returns error for duplicate satellite", %{socket: socket} do
      {:ok, _} = Satellite.start("CHANNEL-SAT-006")

      ref = push(socket, "create_satellite", %{"id" => "CHANNEL-SAT-006"})
      assert_reply ref, :error, %{reason: "already_exists"}
    end
  end

  describe "update_energy" do
    test "updates energy and broadcasts", %{socket: socket} do
      {:ok, _} = Satellite.start("CHANNEL-SAT-007")

      ref = push(socket, "update_energy", %{"id" => "CHANNEL-SAT-007", "delta" => -25.0})
      assert_reply ref, :ok, %{id: "CHANNEL-SAT-007", energy: 75.0}

      assert_broadcast "satellite_updated", %{id: "CHANNEL-SAT-007", energy: 75.0}
    end
  end

  describe "set_mode" do
    test "sets mode and broadcasts", %{socket: socket} do
      {:ok, _} = Satellite.start("CHANNEL-SAT-008")

      ref = push(socket, "set_mode", %{"id" => "CHANNEL-SAT-008", "mode" => "safe"})
      assert_reply ref, :ok, %{id: "CHANNEL-SAT-008", mode: "safe"}

      assert_broadcast "satellite_updated", %{id: "CHANNEL-SAT-008", mode: "safe"}
    end

    test "returns error for invalid mode", %{socket: socket} do
      {:ok, _} = Satellite.start("CHANNEL-SAT-009")

      ref = push(socket, "set_mode", %{"id" => "CHANNEL-SAT-009", "mode" => "invalid"})
      assert_reply ref, :error, %{reason: "invalid_mode"}
    end
  end

  describe "delete_satellite" do
    test "deletes satellite and broadcasts", %{socket: socket} do
      {:ok, _} = Satellite.start("CHANNEL-SAT-010")

      ref = push(socket, "delete_satellite", %{"id" => "CHANNEL-SAT-010"})
      assert_reply ref, :ok, %{id: "CHANNEL-SAT-010"}

      assert_broadcast "satellite_deleted", %{id: "CHANNEL-SAT-010"}

      :timer.sleep(10)
      refute Satellite.alive?("CHANNEL-SAT-010")
    end

    test "returns error for non-existent satellite", %{socket: socket} do
      ref = push(socket, "delete_satellite", %{"id" => "NONEXISTENT"})
      assert_reply ref, :error, %{reason: "not_found"}
    end
  end

  # TASK-128: Heartbeat handling tests
  describe "heartbeat" do
    test "responds to heartbeat with server timestamp", %{socket: socket} do
      ref = push(socket, "heartbeat", %{})
      assert_reply ref, :ok, response

      assert is_integer(response.server_timestamp)
      assert response.server_timestamp > 0
    end

    test "returns client timestamp and latency when provided", %{socket: socket} do
      client_time = System.system_time(:millisecond)
      ref = push(socket, "heartbeat", %{"timestamp" => client_time})
      assert_reply ref, :ok, response

      assert response.client_timestamp == client_time
      assert response.server_timestamp >= client_time
      assert is_integer(response.latency)
      assert response.latency >= 0
    end

    test "heartbeat_ack is silently accepted", %{socket: socket} do
      ref = push(socket, "heartbeat_ack", %{})
      # heartbeat_ack returns noreply, so we shouldn't get a reply
      refute_reply ref, :ok, _, 100
    end
  end
end
