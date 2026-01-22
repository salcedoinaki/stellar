defmodule StellarCore.OrbitalTest do
  use ExUnit.Case, async: false

  alias StellarCore.Orbital
  alias StellarCore.Orbital.Cache
  alias StellarCore.Orbital.CircuitBreaker

  # ISS TLE (example - will be outdated but works for testing)
  @iss_tle_line1 "1 25544U 98067A   24001.50000000  .00016717  00000-0  10270-3 0  9025"
  @iss_tle_line2 "2 25544  51.6400 208.9163 0006703 130.5360 325.0288 15.50377579999999"

  setup do
    # Clear cache before each test
    Cache.clear()
    # Reset circuit breaker
    :fuse.reset(:orbital_service)
    :ok
  end

  describe "propagate_position/4" do
    test "returns position data with valid inputs" do
      timestamp = DateTime.utc_now() |> DateTime.to_unix()
      
      assert {:ok, result} = Orbital.propagate_position(
        "ISS",
        @iss_tle_line1,
        @iss_tle_line2,
        timestamp
      )

      assert result.satellite_id == "ISS"
      assert result.timestamp_unix == timestamp
      
      # Position should be present
      assert is_map(result.position)
      assert is_float(result.position.x_km)
      assert is_float(result.position.y_km)
      assert is_float(result.position.z_km)

      # Velocity should be present
      assert is_map(result.velocity)
      assert is_float(result.velocity.vx_km_s)
      assert is_float(result.velocity.vy_km_s)
      assert is_float(result.velocity.vz_km_s)

      # Geodetic coordinates should be present
      assert is_map(result.geodetic)
      assert result.geodetic.latitude_deg >= -90 and result.geodetic.latitude_deg <= 90
      assert result.geodetic.longitude_deg >= -180 and result.geodetic.longitude_deg <= 180
      assert result.geodetic.altitude_km > 0
    end

    test "accepts DateTime as timestamp" do
      datetime = DateTime.utc_now()
      
      assert {:ok, result} = Orbital.propagate_position(
        "SAT-1",
        @iss_tle_line1,
        @iss_tle_line2,
        datetime
      )

      assert result.timestamp_unix == DateTime.to_unix(datetime)
    end

    test "accepts Unix integer as timestamp" do
      unix_ts = 1704067200  # 2024-01-01 00:00:00 UTC
      
      assert {:ok, result} = Orbital.propagate_position(
        "SAT-2",
        @iss_tle_line1,
        @iss_tle_line2,
        unix_ts
      )

      assert result.timestamp_unix == unix_ts
    end
  end

  describe "propagate_trajectory/6" do
    test "returns trajectory points over time range" do
      start_time = DateTime.utc_now() |> DateTime.to_unix()
      end_time = start_time + 3600  # 1 hour later
      step = 60  # 1 minute intervals

      assert {:ok, points} = Orbital.propagate_trajectory(
        "ISS",
        @iss_tle_line1,
        @iss_tle_line2,
        start_time,
        end_time,
        step
      )

      # Should have 61 points (0 to 60 minutes inclusive)
      assert length(points) == 61

      # Each point should have required fields
      Enum.each(points, fn point ->
        assert is_integer(point.timestamp_unix)
        assert is_map(point.position)
        assert is_map(point.geodetic)
      end)

      # Points should be in chronological order
      timestamps = Enum.map(points, & &1.timestamp_unix)
      assert timestamps == Enum.sort(timestamps)
    end

    test "uses default step of 60 seconds" do
      start_time = 1704067200
      end_time = start_time + 300  # 5 minutes

      assert {:ok, points} = Orbital.propagate_trajectory(
        "SAT-1",
        @iss_tle_line1,
        @iss_tle_line2,
        start_time,
        end_time
      )

      # 0, 60, 120, 180, 240, 300 = 6 points
      assert length(points) == 6
    end
  end

  describe "calculate_visibility/6" do
    test "returns visibility passes" do
      ground_station = %{
        id: "GS-1",
        name: "Test Ground Station",
        latitude_deg: 40.7128,
        longitude_deg: -74.0060,
        altitude_m: 10.0,
        min_elevation_deg: 5.0
      }

      start_time = DateTime.utc_now() |> DateTime.to_unix()
      end_time = start_time + 86400  # 24 hours

      assert {:ok, passes} = Orbital.calculate_visibility(
        "ISS",
        @iss_tle_line1,
        @iss_tle_line2,
        ground_station,
        start_time,
        end_time
      )

      assert is_list(passes)
      
      # Each pass should have required fields
      Enum.each(passes, fn pass ->
        assert is_integer(pass.aos_timestamp)
        assert is_integer(pass.los_timestamp)
        assert pass.los_timestamp > pass.aos_timestamp
        assert is_number(pass.max_elevation_deg)
        assert is_integer(pass.duration_seconds)
      end)
    end
  end

  describe "health_check/0" do
    test "returns health info when service is available" do
      assert {:ok, health} = Orbital.health_check()
      
      assert health.healthy == true
      assert is_binary(health.version)
      assert is_integer(health.uptime_seconds)
    end
  end
end
