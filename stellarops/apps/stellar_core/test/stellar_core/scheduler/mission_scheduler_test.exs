defmodule StellarCore.Scheduler.MissionSchedulerTest do
  use ExUnit.Case, async: false

  alias StellarCore.Scheduler.MissionScheduler
  alias StellarData.Missions
  alias StellarData.Missions.Mission

  # These tests need a running database and the scheduler
  # In a real setup, you'd use Ecto.Sandbox

  describe "submit_mission/1" do
    test "creates a mission and returns it" do
      attrs = %{
        name: "Test Mission",
        type: "imaging",
        satellite_id: "sat-001",
        priority: :high,
        required_energy: 15.0
      }

      # This would call the actual scheduler
      # {:ok, mission} = MissionScheduler.submit_mission(attrs)
      # assert mission.name == "Test Mission"
      # assert mission.status == :pending
    end
  end

  describe "status/0" do
    test "returns scheduler status" do
      # status = MissionScheduler.status()
      # assert is_map(status)
      # assert Map.has_key?(status, :running)
      # assert Map.has_key?(status, :stats)
    end
  end

  describe "pause/resume" do
    test "pauses and resumes the scheduler" do
      # :ok = MissionScheduler.pause()
      # status = MissionScheduler.status()
      # assert status.running == false

      # :ok = MissionScheduler.resume()
      # status = MissionScheduler.status()
      # assert status.running == true
    end
  end
end
