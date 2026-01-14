defmodule StellarData.GroundStations.ContactWindowTest do
  use ExUnit.Case, async: true

  alias StellarData.GroundStations.ContactWindow

  describe "changeset/2" do
    test "valid changeset with required fields" do
      now = DateTime.utc_now()
      future = DateTime.add(now, 600, :second)  # 10 minutes later

      attrs = %{
        satellite_id: "sat-001",
        ground_station_id: Ecto.UUID.generate(),
        aos: now,
        los: future
      }

      changeset = ContactWindow.changeset(%ContactWindow{}, attrs)
      assert changeset.valid?
    end

    test "invalid without required fields" do
      changeset = ContactWindow.changeset(%ContactWindow{}, %{})
      refute changeset.valid?
      assert Keyword.has_key?(changeset.errors, :satellite_id)
      assert Keyword.has_key?(changeset.errors, :ground_station_id)
      assert Keyword.has_key?(changeset.errors, :aos)
      assert Keyword.has_key?(changeset.errors, :los)
    end

    test "validates los is after aos" do
      now = DateTime.utc_now()
      past = DateTime.add(now, -600, :second)

      attrs = %{
        satellite_id: "sat-001",
        ground_station_id: Ecto.UUID.generate(),
        aos: now,
        los: past  # Invalid: before AOS
      }

      changeset = ContactWindow.changeset(%ContactWindow{}, attrs)
      refute changeset.valid?
      assert Keyword.has_key?(changeset.errors, :los)
    end

    test "validates max elevation is in valid range" do
      now = DateTime.utc_now()
      future = DateTime.add(now, 600, :second)

      attrs = %{
        satellite_id: "sat-001",
        ground_station_id: Ecto.UUID.generate(),
        aos: now,
        los: future,
        max_elevation: 100.0  # Invalid: > 90
      }

      changeset = ContactWindow.changeset(%ContactWindow{}, attrs)
      refute changeset.valid?
      assert Keyword.has_key?(changeset.errors, :max_elevation)
    end

    test "accepts valid status values" do
      now = DateTime.utc_now()
      future = DateTime.add(now, 600, :second)

      for status <- [:scheduled, :active, :completed, :missed] do
        attrs = %{
          satellite_id: "sat-001",
          ground_station_id: Ecto.UUID.generate(),
          aos: now,
          los: future,
          status: status
        }

        changeset = ContactWindow.changeset(%ContactWindow{}, attrs)
        assert changeset.valid?
      end
    end

    test "auto-calculates duration when not provided" do
      now = DateTime.utc_now()
      future = DateTime.add(now, 600, :second)

      attrs = %{
        satellite_id: "sat-001",
        ground_station_id: Ecto.UUID.generate(),
        aos: now,
        los: future
      }

      changeset = ContactWindow.changeset(%ContactWindow{}, attrs)
      assert Ecto.Changeset.get_change(changeset, :duration_seconds) == 600
    end
  end

  describe "allocate_changeset/2" do
    test "allocates bandwidth" do
      window = %ContactWindow{allocated_bandwidth: 0.0}
      changeset = ContactWindow.allocate_changeset(window, 100.0)

      assert Ecto.Changeset.get_change(changeset, :allocated_bandwidth) == 100.0
    end

    test "validates bandwidth is non-negative" do
      window = %ContactWindow{allocated_bandwidth: 0.0}
      changeset = ContactWindow.allocate_changeset(window, -10.0)

      refute changeset.valid?
      assert Keyword.has_key?(changeset.errors, :allocated_bandwidth)
    end
  end

  describe "activate_changeset/1" do
    test "updates status to active" do
      window = %ContactWindow{status: :scheduled}
      changeset = ContactWindow.activate_changeset(window)

      assert Ecto.Changeset.get_change(changeset, :status) == :active
    end
  end

  describe "complete_changeset/2" do
    test "updates status to completed with data transferred" do
      window = %ContactWindow{status: :active}
      changeset = ContactWindow.complete_changeset(window, 1024.0)

      assert Ecto.Changeset.get_change(changeset, :status) == :completed
      assert Ecto.Changeset.get_change(changeset, :data_transferred) == 1024.0
    end
  end

  describe "duration calculation" do
    test "calculates duration in seconds from aos and los" do
      now = DateTime.utc_now()
      future = DateTime.add(now, 600, :second)

      # Duration is calculated during changeset
      attrs = %{
        satellite_id: "sat-001",
        ground_station_id: Ecto.UUID.generate(),
        aos: now,
        los: future
      }

      changeset = ContactWindow.changeset(%ContactWindow{}, attrs)
      assert Ecto.Changeset.get_change(changeset, :duration_seconds) == 600
    end
  end
end
