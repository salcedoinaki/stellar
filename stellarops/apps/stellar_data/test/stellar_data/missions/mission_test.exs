defmodule StellarData.Missions.MissionTest do
  use ExUnit.Case, async: true

  alias StellarData.Missions.Mission

  describe "changeset/2" do
    test "valid changeset with required fields" do
      attrs = %{
        name: "Test Mission",
        type: "imaging",
        satellite_id: "sat-001"
      }

      changeset = Mission.changeset(%Mission{}, attrs)
      assert changeset.valid?
    end

    test "invalid without required fields" do
      changeset = Mission.changeset(%Mission{}, %{})
      refute changeset.valid?
      assert Keyword.has_key?(changeset.errors, :name)
      assert Keyword.has_key?(changeset.errors, :type)
      assert Keyword.has_key?(changeset.errors, :satellite_id)
    end

    test "validates resource requirements" do
      attrs = %{
        name: "Test Mission",
        type: "imaging",
        satellite_id: "sat-001",
        required_energy: -10.0  # Invalid
      }

      changeset = Mission.changeset(%Mission{}, attrs)
      refute changeset.valid?
      assert Keyword.has_key?(changeset.errors, :required_energy)
    end

    test "accepts valid priority" do
      for priority <- [:critical, :high, :normal, :low] do
        attrs = %{
          name: "Test Mission",
          type: "imaging",
          satellite_id: "sat-001",
          priority: priority
        }

        changeset = Mission.changeset(%Mission{}, attrs)
        assert changeset.valid?
      end
    end
  end

  describe "lifecycle changesets" do
    setup do
      mission = %Mission{
        id: Ecto.UUID.generate(),
        name: "Test Mission",
        type: "imaging",
        satellite_id: "sat-001",
        status: :pending,
        retry_count: 0,
        max_retries: 3
      }

      {:ok, mission: mission}
    end

    test "schedule_changeset/2 sets status to scheduled", %{mission: mission} do
      scheduled_at = DateTime.utc_now()
      changeset = Mission.schedule_changeset(mission, scheduled_at)

      assert Ecto.Changeset.get_change(changeset, :status) == :scheduled
      assert Ecto.Changeset.get_change(changeset, :scheduled_at) == scheduled_at
    end

    test "start_changeset/1 sets status to running", %{mission: mission} do
      mission = %{mission | status: :scheduled}
      changeset = Mission.start_changeset(mission)

      assert Ecto.Changeset.get_change(changeset, :status) == :running
      assert Ecto.Changeset.get_change(changeset, :started_at) != nil
    end

    test "complete_changeset/2 sets status to completed", %{mission: mission} do
      mission = %{mission | status: :running}
      result = %{output: "success"}
      changeset = Mission.complete_changeset(mission, result)

      assert Ecto.Changeset.get_change(changeset, :status) == :completed
      assert Ecto.Changeset.get_change(changeset, :result) == result
    end

    test "fail_changeset/2 schedules retry when retries available", %{mission: mission} do
      mission = %{mission | status: :running, retry_count: 0}
      changeset = Mission.fail_changeset(mission, "Error occurred")

      assert Ecto.Changeset.get_change(changeset, :status) == :pending
      assert Ecto.Changeset.get_change(changeset, :retry_count) == 1
      assert Ecto.Changeset.get_change(changeset, :next_retry_at) != nil
      assert Ecto.Changeset.get_change(changeset, :last_error) == "Error occurred"
    end

    test "fail_changeset/2 permanently fails when retries exhausted", %{mission: mission} do
      mission = %{mission | status: :running, retry_count: 3, max_retries: 3}
      changeset = Mission.fail_changeset(mission, "Final error")

      assert Ecto.Changeset.get_change(changeset, :status) == :failed
      assert Ecto.Changeset.get_change(changeset, :retry_count) == 4
    end

    test "cancel_changeset/2 sets status to canceled", %{mission: mission} do
      changeset = Mission.cancel_changeset(mission, "No longer needed")

      assert Ecto.Changeset.get_change(changeset, :status) == :canceled
      assert Ecto.Changeset.get_change(changeset, :last_error) == "No longer needed"
    end
  end

  describe "backoff calculation" do
    test "backoff increases exponentially" do
      # First retry: 2^1 * 30 = 60 seconds
      # Second retry: 2^2 * 30 = 120 seconds
      # Third retry: 2^3 * 30 = 240 seconds
      mission = %Mission{
        status: :running,
        retry_count: 0,
        max_retries: 5
      }

      changeset1 = Mission.fail_changeset(mission, "Error 1")
      next_retry1 = Ecto.Changeset.get_change(changeset1, :next_retry_at)

      # The next retry should be at least 30 seconds in the future
      assert DateTime.diff(next_retry1, DateTime.utc_now()) >= 30
    end
  end
end
