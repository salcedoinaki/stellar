defmodule StellarData.Telemetry.TelemetryEventTest do
  use StellarData.DataCase, async: true

  alias StellarData.Satellites.Satellite
  alias StellarData.Telemetry.TelemetryEvent
  alias StellarData.Repo

  setup do
    {:ok, satellite} =
      %Satellite{}
      |> Satellite.changeset(%{id: "telemetry-test-sat", name: "Telemetry Test"})
      |> Repo.insert()

    %{satellite: satellite}
  end

  describe "changeset/2" do
    test "valid changeset with required fields", %{satellite: satellite} do
      attrs = %{
        satellite_id: satellite.id,
        event_type: "energy_update",
        recorded_at: DateTime.utc_now()
      }

      changeset = TelemetryEvent.changeset(%TelemetryEvent{}, attrs)
      assert changeset.valid?
    end

    test "invalid changeset without satellite_id" do
      attrs = %{event_type: "test", recorded_at: DateTime.utc_now()}

      changeset = TelemetryEvent.changeset(%TelemetryEvent{}, attrs)
      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).satellite_id
    end

    test "invalid changeset without event_type", %{satellite: satellite} do
      attrs = %{satellite_id: satellite.id, recorded_at: DateTime.utc_now()}

      changeset = TelemetryEvent.changeset(%TelemetryEvent{}, attrs)
      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).event_type
    end

    test "invalid changeset without recorded_at", %{satellite: satellite} do
      attrs = %{satellite_id: satellite.id, event_type: "test"}

      changeset = TelemetryEvent.changeset(%TelemetryEvent{}, attrs)
      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).recorded_at
    end

    test "validates event_type length", %{satellite: satellite} do
      # Too long
      long_type = String.duplicate("a", 101)
      attrs = %{
        satellite_id: satellite.id,
        event_type: long_type,
        recorded_at: DateTime.utc_now()
      }

      changeset = TelemetryEvent.changeset(%TelemetryEvent{}, attrs)
      refute changeset.valid?
      assert "should be at most 100 character(s)" in errors_on(changeset).event_type
    end

    test "accepts data as map", %{satellite: satellite} do
      attrs = %{
        satellite_id: satellite.id,
        event_type: "mode_change",
        recorded_at: DateTime.utc_now(),
        data: %{
          "old_mode" => "safe",
          "new_mode" => "science",
          "reason" => "scheduled transition"
        }
      }

      changeset = TelemetryEvent.changeset(%TelemetryEvent{}, attrs)
      assert changeset.valid?

      {:ok, event} = Repo.insert(changeset)
      assert event.data["old_mode"] == "safe"
    end

    test "foreign key constraint is enforced" do
      attrs = %{
        satellite_id: "nonexistent-sat",
        event_type: "test",
        recorded_at: DateTime.utc_now()
      }

      assert {:error, changeset} =
               %TelemetryEvent{}
               |> TelemetryEvent.changeset(attrs)
               |> Repo.insert()

      assert "does not exist" in errors_on(changeset).satellite_id
    end
  end
end
