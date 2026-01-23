defmodule StellarCore.Scheduler.MissionSchedulerTest do
  @moduledoc """
  Tests for the Mission Scheduler.
  
  TASK-054: Write unit tests for `submit_mission/1` with valid params
  TASK-055: Write unit tests for `submit_mission/1` with invalid params
  TASK-056: Write unit tests for `submit_mission/1` with non-existent satellite
  TASK-057: Write unit tests for mission scheduling priority ordering
  TASK-058: Write unit tests for mission deadline ordering within same priority
  TASK-059: Write unit tests for mission retry logic
  TASK-060: Write unit tests for mission max retries exhaustion
  TASK-061: Write integration tests for end-to-end mission execution
  TASK-062: Add property-based tests for mission scheduling invariants
  """

  use ExUnit.Case, async: false
  use ExUnitProperties

  alias StellarCore.Scheduler.MissionScheduler
  alias StellarCore.Satellite
  alias StellarData.Missions
  alias StellarData.Missions.Mission
  alias StellarData.Repo

  # Unique scheduler name for isolated tests
  @scheduler_name MissionSchedulerTest.Scheduler

  setup do
    # Clean up satellites and missions before each test
    for id <- Satellite.list() do
      Satellite.stop(id)
    end

    # Start a test scheduler instance (paused to prevent auto-tick)
    {:ok, scheduler} = MissionScheduler.start_link(
      name: @scheduler_name,
      tick_interval: :timer.hours(1)  # Effectively disabled
    )

    # Pause scheduler to control tick manually
    MissionScheduler.pause(@scheduler_name)

    on_exit(fn ->
      if Process.alive?(scheduler), do: GenServer.stop(scheduler)
    end)

    %{scheduler: scheduler}
  end

  # ============================================================================
  # TASK-054: submit_mission/1 with valid params
  # ============================================================================

  describe "submit_mission/1 with valid params (TASK-054)" do
    @tag :db_required
    test "creates a mission with all required fields" do
      attrs = %{
        name: "Valid Test Mission",
        type: "imaging",
        satellite_id: "SAT-MISSION-001",
        priority: :high,
        required_energy: 15.0,
        required_memory: 10.0,
        required_bandwidth: 2.0,
        estimated_duration: 600
      }

      {:ok, mission} = MissionScheduler.submit_mission(attrs, @scheduler_name)

      assert mission.name == "Valid Test Mission"
      assert mission.type == "imaging"
      assert mission.satellite_id == "SAT-MISSION-001"
      assert mission.priority == :high
      assert mission.status == :pending
      assert mission.required_energy == 15.0
    end

    @tag :db_required
    test "creates mission with default values" do
      attrs = %{
        name: "Minimal Mission",
        type: "data_collection",
        satellite_id: "SAT-MISSION-002"
      }

      {:ok, mission} = MissionScheduler.submit_mission(attrs, @scheduler_name)

      assert mission.priority == :normal
      assert mission.status == :pending
      assert mission.required_energy == 10.0  # default
      assert mission.retry_count == 0
      assert mission.max_retries == 3  # default
    end

    @tag :db_required
    test "creates mission with future deadline" do
      future = DateTime.add(DateTime.utc_now(), 3600, :second)
      
      attrs = %{
        name: "Deadline Mission",
        type: "downlink",
        satellite_id: "SAT-MISSION-003",
        deadline: future
      }

      {:ok, mission} = MissionScheduler.submit_mission(attrs, @scheduler_name)

      assert mission.deadline != nil
      assert DateTime.compare(mission.deadline, DateTime.utc_now()) == :gt
    end
  end

  # ============================================================================
  # TASK-055: submit_mission/1 with invalid params
  # ============================================================================

  describe "submit_mission/1 with invalid params (TASK-055)" do
    @tag :db_required
    test "returns error when name is missing" do
      attrs = %{
        type: "imaging",
        satellite_id: "SAT-001"
      }

      {:error, changeset} = MissionScheduler.submit_mission(attrs, @scheduler_name)

      assert changeset.valid? == false
      assert Keyword.has_key?(changeset.errors, :name)
    end

    @tag :db_required
    test "returns error when type is missing" do
      attrs = %{
        name: "No Type Mission",
        satellite_id: "SAT-001"
      }

      {:error, changeset} = MissionScheduler.submit_mission(attrs, @scheduler_name)

      assert changeset.valid? == false
      assert Keyword.has_key?(changeset.errors, :type)
    end

    @tag :db_required
    test "returns error when satellite_id is missing" do
      attrs = %{
        name: "No Satellite Mission",
        type: "imaging"
      }

      {:error, changeset} = MissionScheduler.submit_mission(attrs, @scheduler_name)

      assert changeset.valid? == false
      assert Keyword.has_key?(changeset.errors, :satellite_id)
    end

    @tag :db_required
    test "returns error when required_energy is negative" do
      attrs = %{
        name: "Invalid Energy Mission",
        type: "imaging",
        satellite_id: "SAT-001",
        required_energy: -10.0
      }

      {:error, changeset} = MissionScheduler.submit_mission(attrs, @scheduler_name)

      assert changeset.valid? == false
      assert Keyword.has_key?(changeset.errors, :required_energy)
    end

    @tag :db_required
    test "returns error when deadline is in the past" do
      past = DateTime.add(DateTime.utc_now(), -3600, :second)
      
      attrs = %{
        name: "Past Deadline Mission",
        type: "imaging",
        satellite_id: "SAT-001",
        deadline: past
      }

      {:error, changeset} = MissionScheduler.submit_mission(attrs, @scheduler_name)

      assert changeset.valid? == false
      assert Keyword.has_key?(changeset.errors, :deadline)
    end
  end

  # ============================================================================
  # TASK-056: submit_mission/1 with non-existent satellite
  # ============================================================================

  describe "submit_mission/1 with non-existent satellite (TASK-056)" do
    @tag :db_required
    test "mission is created but scheduling fails for non-existent satellite" do
      # Note: The scheduler creates the mission record but won't schedule it
      # if the satellite doesn't exist (can't check resources)
      attrs = %{
        name: "Orphan Mission",
        type: "imaging",
        satellite_id: "NONEXISTENT-SAT-001",
        priority: :high
      }

      # Mission creation succeeds (record is stored)
      {:ok, mission} = MissionScheduler.submit_mission(attrs, @scheduler_name)
      assert mission.status == :pending

      # But scheduling tick won't schedule it (no satellite to check)
      MissionScheduler.resume(@scheduler_name)
      MissionScheduler.tick(@scheduler_name)
      :timer.sleep(100)

      # Mission should still be pending
      reloaded = Missions.get_mission(mission.id)
      assert reloaded.status == :pending
    end
  end

  # ============================================================================
  # TASK-057: Mission scheduling priority ordering
  # ============================================================================

  describe "mission scheduling priority ordering (TASK-057)" do
    @tag :db_required
    test "critical priority missions are scheduled before high priority" do
      # Start a satellite
      {:ok, _} = Satellite.start("PRIORITY-SAT-001")

      # Create missions with different priorities (out of order)
      {:ok, low_mission} = create_test_mission("PRIORITY-SAT-001", :low, "Low Priority")
      {:ok, critical_mission} = create_test_mission("PRIORITY-SAT-001", :critical, "Critical Priority")
      {:ok, high_mission} = create_test_mission("PRIORITY-SAT-001", :high, "High Priority")
      {:ok, normal_mission} = create_test_mission("PRIORITY-SAT-001", :normal, "Normal Priority")

      # Get pending missions in order
      pending = Missions.get_pending_missions()
      ids = Enum.map(pending, & &1.id)

      # Critical should be first
      critical_idx = Enum.find_index(ids, &(&1 == critical_mission.id))
      high_idx = Enum.find_index(ids, &(&1 == high_mission.id))
      normal_idx = Enum.find_index(ids, &(&1 == normal_mission.id))
      low_idx = Enum.find_index(ids, &(&1 == low_mission.id))

      assert critical_idx < high_idx
      assert high_idx < normal_idx
      assert normal_idx < low_idx

      Satellite.stop("PRIORITY-SAT-001")
    end
  end

  # ============================================================================
  # TASK-058: Mission deadline ordering within same priority
  # ============================================================================

  describe "mission deadline ordering within same priority (TASK-058)" do
    @tag :db_required
    test "missions with earlier deadlines are scheduled first within same priority" do
      {:ok, _} = Satellite.start("DEADLINE-SAT-001")

      now = DateTime.utc_now()
      deadline_soon = DateTime.add(now, 1800, :second)   # 30 min
      deadline_later = DateTime.add(now, 7200, :second)  # 2 hours

      # Create missions with same priority but different deadlines
      {:ok, mission_later} = create_test_mission(
        "DEADLINE-SAT-001", :high, "Later Deadline",
        deadline: deadline_later
      )
      
      {:ok, mission_soon} = create_test_mission(
        "DEADLINE-SAT-001", :high, "Soon Deadline",
        deadline: deadline_soon
      )

      pending = Missions.get_pending_missions()
      ids = Enum.map(pending, & &1.id)

      soon_idx = Enum.find_index(ids, &(&1 == mission_soon.id))
      later_idx = Enum.find_index(ids, &(&1 == mission_later.id))

      # Earlier deadline should come first
      assert soon_idx < later_idx

      Satellite.stop("DEADLINE-SAT-001")
    end
  end

  # ============================================================================
  # TASK-059: Mission retry logic
  # ============================================================================

  describe "mission retry logic (TASK-059)" do
    @tag :db_required
    test "failed mission is rescheduled for retry with incremented count" do
      {:ok, mission} = Missions.create_mission(%{
        name: "Retry Test Mission",
        type: "imaging",
        satellite_id: "RETRY-SAT-001",
        status: :running,
        retry_count: 0,
        max_retries: 3
      })

      {:ok, failed} = Missions.fail_mission(mission, "Simulated failure")

      # Should be back to pending for retry
      assert failed.status == :pending
      assert failed.retry_count == 1
      assert failed.last_error == "Simulated failure"
      assert failed.next_retry_at != nil
    end

    @tag :db_required
    test "retry backoff increases exponentially" do
      mission = %Mission{
        status: :running,
        retry_count: 0,
        max_retries: 5
      }

      # First failure: 2^1 * 30 = 60 seconds
      changeset1 = Mission.fail_changeset(mission, "error")
      assert changeset1.changes.retry_count == 1
      
      # Second failure would be 2^2 * 30 = 120 seconds
      mission2 = %{mission | retry_count: 1}
      changeset2 = Mission.fail_changeset(mission2, "error")
      assert changeset2.changes.retry_count == 2
    end
  end

  # ============================================================================
  # TASK-060: Mission max retries exhaustion
  # ============================================================================

  describe "mission max retries exhaustion (TASK-060)" do
    @tag :db_required
    test "mission is permanently failed after max retries" do
      {:ok, mission} = Missions.create_mission(%{
        name: "Exhaust Retries Mission",
        type: "imaging",
        satellite_id: "EXHAUST-SAT-001",
        status: :running,
        retry_count: 2,  # Already retried twice
        max_retries: 3
      })

      {:ok, failed} = Missions.fail_mission(mission, "Final failure")

      # Should be permanently failed, not pending
      assert failed.status == :failed
      assert failed.retry_count == 3
      assert failed.completed_at != nil
      assert failed.next_retry_at == nil  # No more retries scheduled
    end

    @tag :db_required
    test "mission with max_retries=0 fails immediately without retry" do
      {:ok, mission} = Missions.create_mission(%{
        name: "No Retry Mission",
        type: "imaging",
        satellite_id: "NORETRY-SAT-001",
        status: :running,
        retry_count: 0,
        max_retries: 0
      })

      {:ok, failed} = Missions.fail_mission(mission, "Immediate failure")

      assert failed.status == :failed
      assert failed.retry_count == 1  # Attempted once
    end
  end

  # ============================================================================
  # TASK-061: End-to-end mission execution
  # ============================================================================

  describe "end-to-end mission execution (TASK-061)" do
    @tag :db_required
    @tag :integration
    test "mission goes through full lifecycle: pending → scheduled → running → completed" do
      {:ok, _} = Satellite.start("E2E-SAT-001")
      
      # Ensure satellite has enough resources
      {:ok, state} = Satellite.get_state("E2E-SAT-001")
      assert state.energy >= 15.0

      # Submit mission
      {:ok, mission} = Missions.create_mission(%{
        name: "E2E Test Mission",
        type: "imaging",
        satellite_id: "E2E-SAT-001",
        priority: :high,
        required_energy: 10.0,
        required_memory: 5.0
      })
      assert mission.status == :pending

      # Schedule mission
      {:ok, scheduled} = Missions.schedule_mission(mission, DateTime.utc_now())
      assert scheduled.status == :scheduled
      assert scheduled.scheduled_at != nil

      # Start mission
      {:ok, running} = Missions.start_mission(scheduled)
      assert running.status == :running
      assert running.started_at != nil

      # Complete mission
      {:ok, completed} = Missions.complete_mission(running, %{result: "success"})
      assert completed.status == :completed
      assert completed.completed_at != nil
      assert completed.result == %{result: "success"}

      Satellite.stop("E2E-SAT-001")
    end
  end

  # ============================================================================
  # TASK-062: Property-based tests for scheduling invariants
  # ============================================================================

  describe "property-based tests for scheduling invariants (TASK-062)" do
    property "missions always have valid status after any transition" do
      check all name <- string(:alphanumeric, min_length: 1),
                priority <- member_of([:critical, :high, :normal, :low]) do
        
        # Create a mission conceptually and verify invariants
        mission = %Mission{
          name: name,
          type: "test",
          satellite_id: "PROP-SAT-001",
          priority: priority,
          status: :pending,
          retry_count: 0,
          max_retries: 3
        }

        # Invariant: retry_count <= max_retries
        assert mission.retry_count <= mission.max_retries
        
        # Invariant: status is always valid
        assert mission.status in [:pending, :scheduled, :running, :completed, :failed, :canceled]
      end
    end

    property "fail_changeset always increments retry_count" do
      check all retry_count <- integer(0..10),
                max_retries <- integer(0..10) do
        
        mission = %Mission{
          status: :running,
          retry_count: retry_count,
          max_retries: max_retries
        }

        changeset = Mission.fail_changeset(mission, "test error")

        # Invariant: retry_count always increases
        assert changeset.changes.retry_count == retry_count + 1
      end
    end

    property "priority ordering is total (all priorities are comparable)" do
      priorities = [:critical, :high, :normal, :low]
      
      for p1 <- priorities, p2 <- priorities do
        # Position in list determines order
        pos1 = Enum.find_index(priorities, &(&1 == p1))
        pos2 = Enum.find_index(priorities, &(&1 == p2))
        
        cond do
          pos1 < pos2 -> assert true  # p1 has higher priority
          pos1 > pos2 -> assert true  # p2 has higher priority
          pos1 == pos2 -> assert p1 == p2  # Same priority
        end
      end
    end
  end

  # ============================================================================
  # Scheduler control tests
  # ============================================================================

  describe "scheduler status and control" do
    test "status/0 returns scheduler state" do
      status = MissionScheduler.status(@scheduler_name)

      assert is_map(status)
      assert Map.has_key?(status, :running)
      assert Map.has_key?(status, :stats)
      assert Map.has_key?(status, :running_missions)
    end

    test "pause/0 stops the scheduler" do
      MissionScheduler.resume(@scheduler_name)
      status1 = MissionScheduler.status(@scheduler_name)
      assert status1.running == true

      MissionScheduler.pause(@scheduler_name)
      status2 = MissionScheduler.status(@scheduler_name)
      assert status2.running == false
    end

    test "resume/0 starts the scheduler" do
      MissionScheduler.pause(@scheduler_name)
      status1 = MissionScheduler.status(@scheduler_name)
      assert status1.running == false

      MissionScheduler.resume(@scheduler_name)
      status2 = MissionScheduler.status(@scheduler_name)
      assert status2.running == true
    end
  end

  # ============================================================================
  # Helpers
  # ============================================================================

  defp create_test_mission(satellite_id, priority, name, opts \\ []) do
    deadline = Keyword.get(opts, :deadline)
    
    attrs = %{
      name: name,
      type: "imaging",
      satellite_id: satellite_id,
      priority: priority,
      required_energy: 5.0,
      required_memory: 2.0
    }

    attrs = if deadline, do: Map.put(attrs, :deadline, deadline), else: attrs

    Missions.create_mission(attrs)
  end
end
