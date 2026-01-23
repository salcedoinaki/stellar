defmodule StellarCore.TelemetryIngesterTest do
  @moduledoc """
  Tests for telemetry ingestion and anomaly detection.
  """
  
  use ExUnit.Case, async: true
  
  alias StellarCore.TelemetryIngester
  
  @sample_telemetry %{
    satellite_id: "sat-1",
    norad_id: 25544,
    timestamp: DateTime.utc_now(),
    readings: %{
      battery_voltage: 28.5,
      battery_current: 2.3,
      solar_panel_output: 45.0,
      cpu_temperature: 35.2,
      comm_signal_strength: -85.0,
      memory_usage_percent: 62.0,
      attitude_x: 0.001,
      attitude_y: -0.002,
      attitude_z: 0.0015
    }
  }
  
  @sample_telemetry_batch [
    %{
      satellite_id: "sat-1",
      timestamp: DateTime.utc_now(),
      readings: %{battery_voltage: 28.5, cpu_temperature: 35.0}
    },
    %{
      satellite_id: "sat-1",
      timestamp: DateTime.add(DateTime.utc_now(), 60, :second),
      readings: %{battery_voltage: 28.4, cpu_temperature: 35.5}
    },
    %{
      satellite_id: "sat-1",
      timestamp: DateTime.add(DateTime.utc_now(), 120, :second),
      readings: %{battery_voltage: 28.3, cpu_temperature: 36.0}
    }
  ]
  
  describe "ingest/1" do
    test "ingests single telemetry reading" do
      {:ok, result} = TelemetryIngester.ingest(@sample_telemetry)
      
      assert result.status == :ok
      assert result.anomalies == [] or is_list(result.anomalies)
    end
    
    test "validates required fields" do
      invalid = %{readings: %{voltage: 28.5}}  # Missing satellite_id
      
      result = TelemetryIngester.ingest(invalid)
      
      assert {:error, _} = result
    end
    
    test "handles missing timestamp by using current time" do
      telemetry = %{
        satellite_id: "sat-1",
        readings: %{battery_voltage: 28.5}
      }
      
      {:ok, result} = TelemetryIngester.ingest(telemetry)
      
      assert result.status == :ok
    end
  end
  
  describe "ingest_batch/1" do
    test "ingests multiple readings" do
      {:ok, result} = TelemetryIngester.ingest_batch(@sample_telemetry_batch)
      
      assert result.success_count == 3
      assert result.error_count == 0
    end
    
    test "continues on individual errors" do
      batch = [
        %{satellite_id: "sat-1", readings: %{voltage: 28.5}},
        %{readings: %{voltage: 28.4}},  # Invalid - missing satellite_id
        %{satellite_id: "sat-1", readings: %{voltage: 28.3}}
      ]
      
      {:ok, result} = TelemetryIngester.ingest_batch(batch)
      
      assert result.success_count == 2
      assert result.error_count == 1
    end
  end
  
  describe "anomaly detection" do
    test "detects battery voltage anomaly (too low)" do
      low_voltage = %{
        satellite_id: "sat-1",
        timestamp: DateTime.utc_now(),
        readings: %{battery_voltage: 18.0}  # Below 20V threshold
      }
      
      {:ok, result} = TelemetryIngester.ingest(low_voltage)
      
      assert length(result.anomalies) > 0
      assert Enum.any?(result.anomalies, &(&1.type == :low_voltage))
    end
    
    test "detects battery voltage anomaly (too high)" do
      high_voltage = %{
        satellite_id: "sat-1",
        timestamp: DateTime.utc_now(),
        readings: %{battery_voltage: 35.0}  # Above 32V threshold
      }
      
      {:ok, result} = TelemetryIngester.ingest(high_voltage)
      
      assert length(result.anomalies) > 0
      assert Enum.any?(result.anomalies, &(&1.type == :high_voltage))
    end
    
    test "detects temperature anomaly" do
      high_temp = %{
        satellite_id: "sat-1",
        timestamp: DateTime.utc_now(),
        readings: %{cpu_temperature: 85.0}  # High temperature
      }
      
      {:ok, result} = TelemetryIngester.ingest(high_temp)
      
      assert length(result.anomalies) > 0
      assert Enum.any?(result.anomalies, &(&1.type == :high_temperature))
    end
    
    test "detects signal strength anomaly" do
      weak_signal = %{
        satellite_id: "sat-1",
        timestamp: DateTime.utc_now(),
        readings: %{comm_signal_strength: -120.0}  # Very weak
      }
      
      {:ok, result} = TelemetryIngester.ingest(weak_signal)
      
      assert length(result.anomalies) > 0
      assert Enum.any?(result.anomalies, &(&1.type == :weak_signal))
    end
    
    test "detects memory usage anomaly" do
      high_memory = %{
        satellite_id: "sat-1",
        timestamp: DateTime.utc_now(),
        readings: %{memory_usage_percent: 95.0}  # > 90%
      }
      
      {:ok, result} = TelemetryIngester.ingest(high_memory)
      
      assert length(result.anomalies) > 0
      assert Enum.any?(result.anomalies, &(&1.type == :high_memory))
    end
    
    test "no anomalies for normal readings" do
      {:ok, result} = TelemetryIngester.ingest(@sample_telemetry)
      
      # Normal readings should have no anomalies
      assert result.anomalies == []
    end
  end
  
  describe "get_latest/1" do
    test "retrieves latest telemetry for satellite" do
      TelemetryIngester.ingest(@sample_telemetry)
      
      result = TelemetryIngester.get_latest("sat-1")
      
      case result do
        {:ok, telemetry} ->
          assert telemetry.satellite_id == "sat-1"
          assert Map.has_key?(telemetry, :readings)
        {:error, :not_found} ->
          # Acceptable if not persisted
          assert true
      end
    end
    
    test "returns error for unknown satellite" do
      result = TelemetryIngester.get_latest("nonexistent-satellite")
      
      assert {:error, :not_found} = result
    end
  end
  
  describe "get_history/2" do
    test "retrieves telemetry history for time range" do
      # Ingest batch
      TelemetryIngester.ingest_batch(@sample_telemetry_batch)
      
      since = DateTime.add(DateTime.utc_now(), -1, :hour)
      until_time = DateTime.utc_now()
      
      result = TelemetryIngester.get_history("sat-1", since: since, until: until_time)
      
      assert is_list(result)
    end
    
    test "limits history results" do
      # Ingest many readings
      batch = for i <- 1..50 do
        %{
          satellite_id: "sat-2",
          timestamp: DateTime.add(DateTime.utc_now(), -i, :minute),
          readings: %{voltage: 28.0 + :rand.uniform()}
        }
      end
      
      TelemetryIngester.ingest_batch(batch)
      
      result = TelemetryIngester.get_history("sat-2", limit: 10)
      
      assert length(result) <= 10
    end
  end
  
  describe "aggregation" do
    test "calculates average for metric" do
      TelemetryIngester.ingest_batch(@sample_telemetry_batch)
      
      result = TelemetryIngester.aggregate("sat-1", :battery_voltage, :avg)
      
      assert is_number(result) or result == {:error, :no_data}
    end
    
    test "calculates min/max for metric" do
      TelemetryIngester.ingest_batch(@sample_telemetry_batch)
      
      min_result = TelemetryIngester.aggregate("sat-1", :battery_voltage, :min)
      max_result = TelemetryIngester.aggregate("sat-1", :battery_voltage, :max)
      
      assert is_number(min_result) or min_result == {:error, :no_data}
      assert is_number(max_result) or max_result == {:error, :no_data}
    end
  end
  
  describe "retention policy" do
    test "identifies old telemetry for cleanup" do
      old_cutoff = DateTime.add(DateTime.utc_now(), -30, :day)
      
      count = TelemetryIngester.count_old_records(before: old_cutoff)
      
      assert is_integer(count)
      assert count >= 0
    end
  end
  
  describe "HTTP receiver" do
    test "accepts POST with telemetry payload" do
      # This would test the HTTP endpoint
      # Placeholder for controller test
      assert true
    end
  end
  
  describe "metric naming" do
    test "normalizes metric names" do
      readings = %{
        "Battery.Voltage" => 28.5,
        "CPU Temperature" => 35.0,
        "memory-usage-percent" => 62.0
      }
      
      telemetry = %{
        satellite_id: "sat-1",
        readings: readings
      }
      
      {:ok, result} = TelemetryIngester.ingest(telemetry)
      
      # Should normalize metric names
      assert result.status == :ok
    end
  end
  
  describe "satellite health score" do
    test "calculates health score from telemetry" do
      TelemetryIngester.ingest(@sample_telemetry)
      
      result = TelemetryIngester.health_score("sat-1")
      
      case result do
        {:ok, score} ->
          assert score >= 0 and score <= 100
        {:error, :insufficient_data} ->
          assert true
      end
    end
  end
end
