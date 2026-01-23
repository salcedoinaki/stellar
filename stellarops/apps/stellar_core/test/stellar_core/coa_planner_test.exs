defmodule StellarCore.COAPlannerTest do
  @moduledoc """
  Tests for the COA Planner module.
  """

  use ExUnit.Case, async: true

  alias StellarCore.COAPlanner

  # ============================================================================
  # TASK-355: COA Generation Tests
  # ============================================================================

  describe "Delta-V Calculations" do
    test "vis_viva calculates orbital velocity correctly" do
      # LEO at 400km altitude
      r = 6371.0 + 400.0  # km from Earth center
      a = r  # circular orbit
      mu = 398600.4418  # km^3/s^2

      velocity = COAPlanner.vis_viva(r, a, mu)

      # Expected: ~7.67 km/s for 400km LEO
      assert_in_delta velocity, 7.67, 0.1
    end

    test "hohmann_dv calculates transfer delta-v correctly" do
      # Transfer from 400km to 500km LEO
      r1 = 6371.0 + 400.0
      r2 = 6371.0 + 500.0
      mu = 398600.4418

      {dv1, dv2} = COAPlanner.hohmann_dv(r1, r2, mu)

      # Both burns should be relatively small for 100km altitude change
      assert dv1 > 0
      assert dv2 > 0
      assert dv1 + dv2 < 0.2  # Total should be less than 200 m/s
    end

    test "inclination_change_dv calculates plane change correctly" do
      velocity = 7.67  # km/s (typical LEO)
      delta_i_deg = 5.0  # 5 degree change

      dv = COAPlanner.inclination_change_dv(velocity, delta_i_deg)

      # Approximate formula: 2*v*sin(di/2)
      expected = 2 * velocity * :math.sin(5.0 * :math.pi / 360)
      assert_in_delta dv, expected, 0.01
    end
  end

  describe "Risk Scoring" do
    test "calculate_risk_score returns value between 0 and 100" do
      # Lower fuel = lower risk
      score = COAPlanner.calculate_risk_score(1.0, 3600.0, 0.7)
      assert score >= 0
      assert score <= 100
    end

    test "higher fuel consumption increases risk" do
      low_fuel_score = COAPlanner.calculate_risk_score(1.0, 3600.0, 0.7)
      high_fuel_score = COAPlanner.calculate_risk_score(10.0, 3600.0, 0.7)

      assert high_fuel_score > low_fuel_score
    end

    test "shorter time to TCA increases risk" do
      long_time_score = COAPlanner.calculate_risk_score(2.0, 86400.0, 0.7)
      short_time_score = COAPlanner.calculate_risk_score(2.0, 3600.0, 0.7)

      assert short_time_score > long_time_score
    end

    test "lower probability improvement increases risk" do
      good_improvement_score = COAPlanner.calculate_risk_score(2.0, 36000.0, 0.9)
      poor_improvement_score = COAPlanner.calculate_risk_score(2.0, 36000.0, 0.3)

      assert poor_improvement_score > good_improvement_score
    end
  end

  describe "Fuel Estimation" do
    test "estimate_fuel returns positive value" do
      # 1 km/s delta-v for 500kg satellite
      fuel = COAPlanner.estimate_fuel(1.0, 500.0, 3100.0)

      assert fuel > 0
      assert fuel < 500.0  # Shouldn't exceed spacecraft mass
    end

    test "estimate_fuel uses Tsiolkovsky equation" do
      delta_v = 0.1  # 100 m/s
      spacecraft_mass = 500.0
      isp = 3100.0

      fuel = COAPlanner.estimate_fuel(delta_v, spacecraft_mass, isp)

      # Verify against Tsiolkovsky: m_fuel = m0 * (1 - exp(-dv / (Isp * g0)))
      g0 = 0.00981  # km/s^2
      ve = isp * g0
      expected = spacecraft_mass * (1 - :math.exp(-delta_v / ve))

      assert_in_delta fuel, expected, 0.1
    end
  end

  describe "Burn Duration" do
    test "estimate_burn_duration returns positive seconds" do
      duration = COAPlanner.estimate_burn_duration(0.1, 50.0, 500.0)

      assert duration > 0
      assert is_number(duration)
    end
  end

  describe "COA Type Generation" do
    test "build_retrograde_coa creates valid COA attrs" do
      conjunction = %{
        id: Ecto.UUID.generate(),
        asset: %{id: "SAT-001", mass_kg: 500.0},
        miss_distance_km: 0.5,
        probability: 0.001,
        tca: DateTime.add(DateTime.utc_now(), 86400, :second)
      }

      satellite_orbit = %{
        "a" => 6771.0,
        "e" => 0.001,
        "i" => 45.0,
        "raan" => 100.0,
        "argp" => 90.0,
        "ta" => 180.0
      }

      attrs = COAPlanner.build_retrograde_coa(conjunction, satellite_orbit)

      assert attrs.type == :retrograde_burn
      assert attrs.conjunction_id == conjunction.id
      assert attrs.delta_v_magnitude > 0
      assert attrs.risk_score >= 0 and attrs.risk_score <= 100
      assert attrs.pre_burn_orbit != nil
      assert attrs.post_burn_orbit != nil
    end

    test "build_inclination_change_coa creates valid COA attrs" do
      conjunction = %{
        id: Ecto.UUID.generate(),
        asset: %{id: "SAT-001", mass_kg: 500.0},
        miss_distance_km: 0.5,
        probability: 0.001,
        tca: DateTime.add(DateTime.utc_now(), 86400, :second)
      }

      satellite_orbit = %{
        "a" => 6771.0,
        "e" => 0.001,
        "i" => 45.0,
        "raan" => 100.0,
        "argp" => 90.0,
        "ta" => 180.0
      }

      attrs = COAPlanner.build_inclination_change_coa(conjunction, satellite_orbit)

      assert attrs.type == :inclination_change
      assert attrs.delta_v_magnitude > 0
      # Inclination should change
      assert attrs.post_burn_orbit["i"] != satellite_orbit["i"]
    end

    test "build_station_keeping_coa has zero delta-v" do
      conjunction = %{
        id: Ecto.UUID.generate(),
        asset: %{id: "SAT-001", mass_kg: 500.0},
        miss_distance_km: 0.5,
        probability: 0.001,
        tca: DateTime.add(DateTime.utc_now(), 86400, :second)
      }

      satellite_orbit = %{
        "a" => 6771.0,
        "e" => 0.001,
        "i" => 45.0
      }

      attrs = COAPlanner.build_station_keeping_coa(conjunction, satellite_orbit)

      assert attrs.type == :station_keeping
      assert attrs.delta_v_magnitude == 0.0
      assert attrs.estimated_fuel_kg == 0.0
    end
  end
end
