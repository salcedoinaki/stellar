defmodule StellarCore.TLEIngester.TLEParserTest do
  @moduledoc """
  Tests for TLE parsing functionality.
  """
  
  use ExUnit.Case, async: true
  
  alias StellarCore.TLEIngester.TLEParser
  
  @valid_tle_lines {
    "ISS (ZARYA)",
    "1 25544U 98067A   24023.50000000  .00016717  00000-0  10270-3 0  9992",
    "2 25544  51.6435  21.8790 0006957 137.3221 264.0235 15.49564538423842"
  }
  
  @valid_tle_3le """
  ISS (ZARYA)
  1 25544U 98067A   24023.50000000  .00016717  00000-0  10270-3 0  9992
  2 25544  51.6435  21.8790 0006957 137.3221 264.0235 15.49564538423842
  """
  
  describe "parse/1" do
    test "parses valid 3-line TLE" do
      {:ok, result} = TLEParser.parse(@valid_tle_3le)
      
      assert result.name == "ISS (ZARYA)"
      assert result.norad_id == 25544
      assert result.international_designator == "98067A"
    end
    
    test "extracts orbital elements correctly" do
      {:ok, result} = TLEParser.parse(@valid_tle_3le)
      
      assert_in_delta result.inclination, 51.6435, 0.001
      assert_in_delta result.raan, 21.8790, 0.001
      assert_in_delta result.eccentricity, 0.0006957, 0.0000001
      assert_in_delta result.argument_of_perigee, 137.3221, 0.001
      assert_in_delta result.mean_anomaly, 264.0235, 0.001
      assert_in_delta result.mean_motion, 15.49564538, 0.00000001
    end
    
    test "parses tuple format" do
      {name, line1, line2} = @valid_tle_lines
      {:ok, result} = TLEParser.parse({name, line1, line2})
      
      assert result.name == "ISS (ZARYA)"
      assert result.norad_id == 25544
    end
    
    test "returns error for invalid line 1" do
      invalid_tle = """
      ISS
      2 25544U 98067A   24023.50000000  .00016717  00000-0  10270-3 0  9992
      2 25544  51.6435  21.8790 0006957 137.3221 264.0235 15.49564538423842
      """
      
      assert {:error, _reason} = TLEParser.parse(invalid_tle)
    end
    
    test "returns error for invalid line 2" do
      invalid_tle = """
      ISS
      1 25544U 98067A   24023.50000000  .00016717  00000-0  10270-3 0  9992
      1 25544  51.6435  21.8790 0006957 137.3221 264.0235 15.49564538423842
      """
      
      assert {:error, _reason} = TLEParser.parse(invalid_tle)
    end
    
    test "returns error for mismatched NORAD IDs" do
      invalid_tle = """
      ISS
      1 25544U 98067A   24023.50000000  .00016717  00000-0  10270-3 0  9992
      2 25545  51.6435  21.8790 0006957 137.3221 264.0235 15.49564538423842
      """
      
      assert {:error, :norad_id_mismatch} = TLEParser.parse(invalid_tle)
    end
  end
  
  describe "validate_checksum/1" do
    test "validates correct line 1 checksum" do
      line1 = "1 25544U 98067A   24023.50000000  .00016717  00000-0  10270-3 0  9992"
      assert TLEParser.validate_checksum(line1) == :ok
    end
    
    test "validates correct line 2 checksum" do
      line2 = "2 25544  51.6435  21.8790 0006957 137.3221 264.0235 15.49564538423842"
      assert TLEParser.validate_checksum(line2) == :ok
    end
    
    test "rejects invalid checksum" do
      # Modified checksum digit
      invalid_line = "1 25544U 98067A   24023.50000000  .00016717  00000-0  10270-3 0  9993"
      assert {:error, :invalid_checksum} = TLEParser.validate_checksum(invalid_line)
    end
  end
  
  describe "calculate_checksum/1" do
    test "calculates correct checksum for line 1" do
      # Line without checksum
      line = "1 25544U 98067A   24023.50000000  .00016717  00000-0  10270-3 0  999"
      assert TLEParser.calculate_checksum(line) == 2
    end
    
    test "handles minus signs as value 1" do
      line = "1 99999U 00001A   24001.00000000 -.00000001  00000-0 -10000-0 0  999"
      checksum = TLEParser.calculate_checksum(line)
      assert is_integer(checksum)
      assert checksum >= 0 and checksum <= 9
    end
  end
  
  describe "parse_epoch/1" do
    test "parses epoch year and day" do
      line1 = "1 25544U 98067A   24023.50000000  .00016717  00000-0  10270-3 0  9992"
      {:ok, epoch} = TLEParser.parse_epoch(line1)
      
      assert epoch.year == 2024
      assert_in_delta epoch.day, 23.5, 0.001
    end
    
    test "handles 20th century years (>56)" do
      line1 = "1 25544U 98067A   98067.50000000  .00016717  00000-0  10270-3 0  9992"
      {:ok, epoch} = TLEParser.parse_epoch(line1)
      
      assert epoch.year == 1998
    end
    
    test "handles 21st century years (<=56)" do
      line1 = "1 25544U 98067A   24023.50000000  .00016717  00000-0  10270-3 0  9992"
      {:ok, epoch} = TLEParser.parse_epoch(line1)
      
      assert epoch.year == 2024
    end
  end
  
  describe "parse_batch/1" do
    test "parses multiple TLEs from text" do
      batch = """
      ISS (ZARYA)
      1 25544U 98067A   24023.50000000  .00016717  00000-0  10270-3 0  9992
      2 25544  51.6435  21.8790 0006957 137.3221 264.0235 15.49564538423842
      TIANGONG
      1 48274U 21035A   24023.50000000  .00012345  00000-0  10270-3 0  9993
      2 48274  41.4700 123.4567 0003210 234.5678 125.4321 15.61234567 12345
      """
      
      {:ok, results} = TLEParser.parse_batch(batch)
      
      assert length(results) == 2
      assert Enum.at(results, 0).name == "ISS (ZARYA)"
      assert Enum.at(results, 1).name == "TIANGONG"
    end
    
    test "handles empty input" do
      {:ok, results} = TLEParser.parse_batch("")
      assert results == []
    end
    
    test "skips invalid TLEs and continues parsing" do
      batch = """
      VALID SAT
      1 25544U 98067A   24023.50000000  .00016717  00000-0  10270-3 0  9992
      2 25544  51.6435  21.8790 0006957 137.3221 264.0235 15.49564538423842
      INVALID SAT
      GARBAGE LINE 1
      GARBAGE LINE 2
      ANOTHER VALID
      1 48274U 21035A   24023.50000000  .00012345  00000-0  10270-3 0  9993
      2 48274  41.4700 123.4567 0003210 234.5678 125.4321 15.61234567 12345
      """
      
      {:ok, results} = TLEParser.parse_batch(batch)
      
      # Should parse valid ones, skip invalid
      assert length(results) >= 1
    end
  end
  
  describe "to_sgp4_elements/1" do
    test "converts parsed TLE to SGP4 format" do
      {:ok, tle} = TLEParser.parse(@valid_tle_3le)
      elements = TLEParser.to_sgp4_elements(tle)
      
      assert Map.has_key?(elements, :satnum)
      assert Map.has_key?(elements, :epochyr)
      assert Map.has_key?(elements, :epochdays)
      assert Map.has_key?(elements, :ndot)
      assert Map.has_key?(elements, :nddot)
      assert Map.has_key?(elements, :bstar)
      assert Map.has_key?(elements, :inclo)
      assert Map.has_key?(elements, :nodeo)
      assert Map.has_key?(elements, :ecco)
      assert Map.has_key?(elements, :argpo)
      assert Map.has_key?(elements, :mo)
      assert Map.has_key?(elements, :no_kozai)
    end
  end
  
  describe "age_hours/1" do
    test "calculates TLE age in hours" do
      # Create TLE with epoch 24 hours ago
      yesterday = DateTime.add(DateTime.utc_now(), -24, :hour)
      
      tle = %{
        epoch: yesterday,
        name: "TEST",
        norad_id: 12345
      }
      
      age = TLEParser.age_hours(tle)
      
      assert_in_delta age, 24.0, 1.0  # Within 1 hour tolerance
    end
    
    test "returns positive age for past epochs" do
      old_epoch = DateTime.add(DateTime.utc_now(), -48, :hour)
      
      tle = %{epoch: old_epoch}
      
      assert TLEParser.age_hours(tle) > 0
    end
  end
end
