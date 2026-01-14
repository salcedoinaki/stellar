defmodule StellarData.TelemetryTest do
  use StellarData.DataCase, async: true

  alias StellarData.Satellites
  alias StellarData.Telemetry

  setup do
    {:ok, satellite} = Satellites.create_satellite(%{id: "telemetry-ctx-sat", name: "Telemetry Context"})
    %{satellite: satellite}
  end

  describe "record_event/3" do
    test "creates event with valid data", %{satellite: satellite} do
      assert {:ok, event} = Telemetry.record_event(satellite.id, "mode_change", %{
        "old_mode" => "nominal",
        "new_mode" => "safe"
      })

      assert event.satellite_id == satellite.id
      assert event.event_type == "mode_change"
      assert event.data["old_mode"] == "nominal"
      assert event.recorded_at != nil
    end

    test "creates event with default empty data", %{satellite: satellite} do
      assert {:ok, event} = Telemetry.record_event(satellite.id, "heartbeat")
      assert event.data == %{}
    end
  end

  describe "get_events/2" do
    test "returns events for satellite in descending order", %{satellite: satellite} do
      {:ok, _} = Telemetry.record_event(satellite.id, "event1")
      Process.sleep(1)
      {:ok, _} = Telemetry.record_event(satellite.id, "event2")

      events = Telemetry.get_events(satellite.id)
      assert length(events) == 2
      assert hd(events).event_type == "event2"
    end

    test "respects limit option", %{satellite: satellite} do
      for i <- 1..5 do
        {:ok, _} = Telemetry.record_event(satellite.id, "event_#{i}")
      end

      events = Telemetry.get_events(satellite.id, limit: 2)
      assert length(events) == 2
    end

    test "filters by event_type", %{satellite: satellite} do
      {:ok, _} = Telemetry.record_event(satellite.id, "heartbeat")
      {:ok, _} = Telemetry.record_event(satellite.id, "mode_change")
      {:ok, _} = Telemetry.record_event(satellite.id, "heartbeat")

      events = Telemetry.get_events(satellite.id, event_type: "heartbeat")
      assert length(events) == 2
      assert Enum.all?(events, &(&1.event_type == "heartbeat"))
    end

    test "filters by since timestamp", %{satellite: satellite} do
      {:ok, old_event} = Telemetry.record_event(satellite.id, "old_event")
      Process.sleep(10)
      since = DateTime.utc_now()
      Process.sleep(10)
      {:ok, _} = Telemetry.record_event(satellite.id, "new_event")

      events = Telemetry.get_events(satellite.id, since: since)
      assert length(events) == 1
      assert hd(events).event_type == "new_event"
      refute Enum.any?(events, &(&1.id == old_event.id))
    end

    test "returns empty list for satellite with no events" do
      assert Telemetry.get_events("nonexistent-sat") == []
    end
  end

  describe "get_latest_event/2" do
    test "returns most recent event", %{satellite: satellite} do
      {:ok, _} = Telemetry.record_event(satellite.id, "first")
      Process.sleep(1)
      {:ok, second} = Telemetry.record_event(satellite.id, "second")

      latest = Telemetry.get_latest_event(satellite.id)
      assert latest.id == second.id
    end

    test "filters by event_type", %{satellite: satellite} do
      {:ok, _} = Telemetry.record_event(satellite.id, "mode_change")
      Process.sleep(1)
      {:ok, heartbeat} = Telemetry.record_event(satellite.id, "heartbeat")
      Process.sleep(1)
      {:ok, _} = Telemetry.record_event(satellite.id, "mode_change")

      latest = Telemetry.get_latest_event(satellite.id, "heartbeat")
      assert latest.id == heartbeat.id
    end

    test "returns nil when no events" do
      assert Telemetry.get_latest_event("nonexistent") == nil
    end
  end

  describe "get_event_counts/1" do
    test "returns counts grouped by event_type", %{satellite: satellite} do
      {:ok, _} = Telemetry.record_event(satellite.id, "heartbeat")
      {:ok, _} = Telemetry.record_event(satellite.id, "heartbeat")
      {:ok, _} = Telemetry.record_event(satellite.id, "mode_change")

      counts = Telemetry.get_event_counts(satellite.id)
      assert counts["heartbeat"] == 2
      assert counts["mode_change"] == 1
    end
  end

  describe "prune_old_events/1" do
    test "deletes events older than specified days", %{satellite: satellite} do
      # Insert event with old timestamp directly
      old_time = DateTime.utc_now() |> DateTime.add(-40 * 24 * 60 * 60, :second)
      
      {:ok, old_event} =
        %StellarData.Telemetry.TelemetryEvent{}
        |> StellarData.Telemetry.TelemetryEvent.changeset(%{
          satellite_id: satellite.id,
          event_type: "old",
          recorded_at: old_time
        })
        |> Repo.insert()

      {:ok, _new_event} = Telemetry.record_event(satellite.id, "new")

      {deleted_count, _} = Telemetry.prune_old_events(30)
      assert deleted_count >= 1

      events = Telemetry.get_events(satellite.id)
      refute Enum.any?(events, &(&1.id == old_event.id))
    end
  end
end
