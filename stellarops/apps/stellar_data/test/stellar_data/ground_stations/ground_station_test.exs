defmodule StellarData.GroundStations.GroundStationTest do
  use ExUnit.Case, async: true

  alias StellarData.GroundStations.GroundStation

  describe "changeset/2" do
    test "valid changeset with required fields" do
      attrs = %{
        name: "Svalbard Ground Station",
        code: "SVALBARD",
        latitude: 78.2306,
        longitude: 15.3894
      }

      changeset = GroundStation.changeset(%GroundStation{}, attrs)
      assert changeset.valid?
    end

    test "invalid without required fields" do
      changeset = GroundStation.changeset(%GroundStation{}, %{})
      refute changeset.valid?
      assert Keyword.has_key?(changeset.errors, :name)
      assert Keyword.has_key?(changeset.errors, :code)
      assert Keyword.has_key?(changeset.errors, :latitude)
      assert Keyword.has_key?(changeset.errors, :longitude)
    end

    test "validates latitude range" do
      attrs = %{
        name: "Invalid Station",
        code: "INVALID",
        latitude: 100.0,  # Invalid: > 90
        longitude: 0.0
      }

      changeset = GroundStation.changeset(%GroundStation{}, attrs)
      refute changeset.valid?
      assert Keyword.has_key?(changeset.errors, :latitude)
    end

    test "validates longitude range" do
      attrs = %{
        name: "Invalid Station",
        code: "INVALID",
        latitude: 0.0,
        longitude: 200.0  # Invalid: > 180
      }

      changeset = GroundStation.changeset(%GroundStation{}, attrs)
      refute changeset.valid?
      assert Keyword.has_key?(changeset.errors, :longitude)
    end

    test "validates bandwidth is positive" do
      attrs = %{
        name: "Test Station",
        code: "TEST",
        latitude: 0.0,
        longitude: 0.0,
        bandwidth_mbps: -10.0  # Invalid
      }

      changeset = GroundStation.changeset(%GroundStation{}, attrs)
      refute changeset.valid?
      assert Keyword.has_key?(changeset.errors, :bandwidth_mbps)
    end

    test "accepts valid status values" do
      for status <- [:online, :offline, :maintenance] do
        attrs = %{
          name: "Test Station",
          code: "TEST-#{status}",
          latitude: 0.0,
          longitude: 0.0,
          status: status
        }

        changeset = GroundStation.changeset(%GroundStation{}, attrs)
        assert changeset.valid?
      end
    end
  end

  describe "status_changeset/2" do
    test "updates status" do
      station = %GroundStation{status: :online}
      changeset = GroundStation.status_changeset(station, :maintenance)

      assert Ecto.Changeset.get_change(changeset, :status) == :maintenance
    end
  end

  describe "load_changeset/2" do
    test "updates current load" do
      station = %GroundStation{current_load: 0.0}
      changeset = GroundStation.load_changeset(station, 50.0)

      assert Ecto.Changeset.get_change(changeset, :current_load) == 50.0
    end

    test "validates load is within 0-100%" do
      station = %GroundStation{current_load: 0.0}
      changeset = GroundStation.load_changeset(station, 150.0)

      refute changeset.valid?
      assert Keyword.has_key?(changeset.errors, :current_load)
    end
  end
end
