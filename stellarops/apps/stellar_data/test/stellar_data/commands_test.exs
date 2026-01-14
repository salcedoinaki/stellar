defmodule StellarData.CommandsTest do
  use StellarData.DataCase, async: true

  alias StellarData.Satellites
  alias StellarData.Commands

  setup do
    {:ok, satellite} = Satellites.create_satellite(%{id: "cmd-ctx-sat", name: "Command Context"})
    %{satellite: satellite}
  end

  describe "create_command/4" do
    test "creates command with valid data", %{satellite: satellite} do
      assert {:ok, command} = Commands.create_command(
        satellite.id,
        "set_mode",
        %{"mode" => "safe"}
      )

      assert command.satellite_id == satellite.id
      assert command.command_type == "set_mode"
      assert command.params["mode"] == "safe"
      assert command.status == :pending
    end

    test "accepts priority option", %{satellite: satellite} do
      assert {:ok, command} = Commands.create_command(
        satellite.id,
        "urgent_cmd",
        %{},
        priority: 50
      )

      assert command.priority == 50
    end

    test "accepts scheduled_at option", %{satellite: satellite} do
      future = DateTime.utc_now() |> DateTime.add(3600, :second)

      assert {:ok, command} = Commands.create_command(
        satellite.id,
        "scheduled_cmd",
        %{},
        scheduled_at: future
      )

      assert command.scheduled_at == future
    end
  end

  describe "get_command/1 and get_command!/1" do
    test "returns command by id", %{satellite: satellite} do
      {:ok, command} = Commands.create_command(satellite.id, "test", %{})

      assert found = Commands.get_command(command.id)
      assert found.id == command.id
    end

    test "get_command returns nil for nonexistent" do
      assert Commands.get_command(-1) == nil
    end

    test "get_command! raises for nonexistent" do
      assert_raise Ecto.NoResultsError, fn ->
        Commands.get_command!(-1)
      end
    end
  end

  describe "get_pending_commands/1" do
    test "returns only pending commands ordered by priority", %{satellite: satellite} do
      {:ok, low} = Commands.create_command(satellite.id, "low", %{}, priority: 10)
      {:ok, high} = Commands.create_command(satellite.id, "high", %{}, priority: 50)
      {:ok, running} = Commands.create_command(satellite.id, "running", %{})
      Commands.start_command(running)

      pending = Commands.get_pending_commands(satellite.id)
      assert length(pending) == 2
      assert hd(pending).id == high.id
      assert List.last(pending).id == low.id
    end
  end

  describe "get_next_command/1" do
    test "returns highest priority ready command", %{satellite: satellite} do
      {:ok, _} = Commands.create_command(satellite.id, "low", %{}, priority: 10)
      {:ok, high} = Commands.create_command(satellite.id, "high", %{}, priority: 50)

      next = Commands.get_next_command(satellite.id)
      assert next.id == high.id
    end

    test "excludes scheduled commands not yet due", %{satellite: satellite} do
      future = DateTime.utc_now() |> DateTime.add(3600, :second)
      {:ok, _scheduled} = Commands.create_command(satellite.id, "scheduled", %{}, scheduled_at: future)
      {:ok, ready} = Commands.create_command(satellite.id, "ready", %{})

      next = Commands.get_next_command(satellite.id)
      assert next.id == ready.id
    end

    test "returns nil when no commands ready" do
      assert Commands.get_next_command("nonexistent") == nil
    end
  end

  describe "start_command/1" do
    test "transitions to running and sets started_at", %{satellite: satellite} do
      {:ok, command} = Commands.create_command(satellite.id, "start_test", %{})

      assert {:ok, started} = Commands.start_command(command)
      assert started.status == :running
      assert started.started_at != nil
    end
  end

  describe "complete_command/2" do
    test "transitions to done and sets completed_at", %{satellite: satellite} do
      {:ok, command} = Commands.create_command(satellite.id, "complete_test", %{})
      {:ok, started} = Commands.start_command(command)

      assert {:ok, completed} = Commands.complete_command(started, %{"success" => true})
      assert completed.status == :done
      assert completed.completed_at != nil
      assert completed.result["success"] == true
    end
  end

  describe "fail_command/2" do
    test "transitions to failed and records error", %{satellite: satellite} do
      {:ok, command} = Commands.create_command(satellite.id, "fail_test", %{})
      {:ok, started} = Commands.start_command(command)

      assert {:ok, failed} = Commands.fail_command(started, "Timeout")
      assert failed.status == :failed
      assert failed.error_message == "Timeout"
      assert failed.completed_at != nil
    end
  end

  describe "cancel_command/1" do
    test "transitions to canceled", %{satellite: satellite} do
      {:ok, command} = Commands.create_command(satellite.id, "cancel_test", %{})

      assert {:ok, canceled} = Commands.cancel_command(command)
      assert canceled.status == :canceled
      assert canceled.completed_at != nil
    end
  end

  describe "get_command_history/2" do
    test "returns commands in descending order", %{satellite: satellite} do
      {:ok, _first} = Commands.create_command(satellite.id, "first", %{})
      {:ok, second} = Commands.create_command(satellite.id, "second", %{})

      history = Commands.get_command_history(satellite.id)
      assert hd(history).id == second.id
    end

    test "respects limit option", %{satellite: satellite} do
      for i <- 1..5 do
        Commands.create_command(satellite.id, "cmd_#{i}", %{})
      end

      history = Commands.get_command_history(satellite.id, limit: 2)
      assert length(history) == 2
    end

    test "filters by status", %{satellite: satellite} do
      {:ok, pending} = Commands.create_command(satellite.id, "pending", %{})
      {:ok, to_cancel} = Commands.create_command(satellite.id, "to_cancel", %{})
      Commands.cancel_command(to_cancel)

      history = Commands.get_command_history(satellite.id, status: :pending)
      assert length(history) == 1
      assert hd(history).id == pending.id
    end
  end

  describe "get_command_counts/1" do
    test "returns counts by status", %{satellite: satellite} do
      {:ok, _} = Commands.create_command(satellite.id, "pending1", %{})
      {:ok, _} = Commands.create_command(satellite.id, "pending2", %{})
      {:ok, to_start} = Commands.create_command(satellite.id, "to_start", %{})
      Commands.start_command(to_start)

      counts = Commands.get_command_counts(satellite.id)
      assert counts[:pending] == 2
      assert counts[:running] == 1
    end
  end
end
