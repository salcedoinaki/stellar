defmodule StellarData.Commands.CommandTest do
  use StellarData.DataCase, async: true

  alias StellarData.Satellites.Satellite
  alias StellarData.Commands.Command
  alias StellarData.Repo

  setup do
    {:ok, satellite} =
      %Satellite{}
      |> Satellite.changeset(%{id: "cmd-test-sat", name: "Command Test"})
      |> Repo.insert()

    %{satellite: satellite}
  end

  describe "changeset/2" do
    test "valid changeset with required fields", %{satellite: satellite} do
      attrs = %{
        satellite_id: satellite.id,
        command_type: "set_mode"
      }

      changeset = Command.changeset(%Command{}, attrs)
      assert changeset.valid?
    end

    test "invalid changeset without command_type", %{satellite: satellite} do
      attrs = %{satellite_id: satellite.id}

      changeset = Command.changeset(%Command{}, attrs)
      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).command_type
    end

    test "invalid changeset without satellite_id" do
      attrs = %{command_type: "test"}

      changeset = Command.changeset(%Command{}, attrs)
      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).satellite_id
    end

    test "validates status inclusion" do
      attrs = %{
        satellite_id: "sat-1",
        command_type: "test",
        status: :invalid_status
      }

      changeset = Command.changeset(%Command{}, attrs)
      refute changeset.valid?
      assert "is invalid" in errors_on(changeset).status
    end

    test "validates priority range", %{satellite: satellite} do
      # Below minimum
      attrs = %{satellite_id: satellite.id, command_type: "test", priority: -1}
      changeset = Command.changeset(%Command{}, attrs)
      refute changeset.valid?
      assert "must be greater than or equal to 0" in errors_on(changeset).priority

      # Above maximum
      attrs = %{satellite_id: satellite.id, command_type: "test", priority: 101}
      changeset = Command.changeset(%Command{}, attrs)
      refute changeset.valid?
      assert "must be less than or equal to 100" in errors_on(changeset).priority
    end

    test "default status is pending", %{satellite: satellite} do
      attrs = %{
        satellite_id: satellite.id,
        command_type: "test"
      }

      {:ok, command} =
        %Command{}
        |> Command.changeset(attrs)
        |> Repo.insert()

      assert command.status == :pending
    end

    test "default priority is 0", %{satellite: satellite} do
      attrs = %{
        satellite_id: satellite.id,
        command_type: "test"
      }

      {:ok, command} =
        %Command{}
        |> Command.changeset(attrs)
        |> Repo.insert()

      assert command.priority == 0
    end
  end

  describe "status_changeset/2" do
    test "valid transition from pending to running", %{satellite: satellite} do
      {:ok, command} =
        %Command{}
        |> Command.changeset(%{satellite_id: satellite.id, command_type: "test"})
        |> Repo.insert()

      changeset = Command.status_changeset(command, %{status: :running})
      assert changeset.valid?
    end

    test "valid transition from pending to canceled", %{satellite: satellite} do
      {:ok, command} =
        %Command{}
        |> Command.changeset(%{satellite_id: satellite.id, command_type: "test"})
        |> Repo.insert()

      changeset = Command.status_changeset(command, %{status: :canceled})
      assert changeset.valid?
    end

    test "valid transition from running to done", %{satellite: satellite} do
      {:ok, command} =
        %Command{}
        |> Command.changeset(%{satellite_id: satellite.id, command_type: "test", status: :running})
        |> Repo.insert()

      changeset = Command.status_changeset(command, %{status: :done})
      assert changeset.valid?
    end

    test "invalid transition from pending to done", %{satellite: satellite} do
      {:ok, command} =
        %Command{}
        |> Command.changeset(%{satellite_id: satellite.id, command_type: "test"})
        |> Repo.insert()

      changeset = Command.status_changeset(command, %{status: :done})
      refute changeset.valid?
      assert "invalid status transition" in errors_on(changeset).status
    end

    test "can set started_at timestamp", %{satellite: satellite} do
      {:ok, command} =
        %Command{}
        |> Command.changeset(%{satellite_id: satellite.id, command_type: "test"})
        |> Repo.insert()

      now = DateTime.utc_now()
      changeset = Command.status_changeset(command, %{status: :running, started_at: now})
      assert changeset.valid?

      {:ok, updated} = Repo.update(changeset)
      assert updated.started_at != nil
    end
  end
end
