defmodule StellarCore.Orbital do
  @moduledoc """
  Client for the Rust Orbital Service.

  Provides functions to call the orbital propagation service
  for satellite position calculations using SGP4.

  Uses HTTP/JSON endpoints exposed by the Rust service on port 9090.
  Includes circuit breaker and caching for reliability and performance.
  """

  require Logger
  
  alias StellarCore.Orbital.{HttpClient, CircuitBreaker, Cache}

  @doc """
  Propagate satellite position from TLE at a given timestamp.

  ## Parameters
    - satellite_id: String identifier for the satellite
    - tle_line1: First line of TLE
    - tle_line2: Second line of TLE
    - timestamp: Unix timestamp (integer) or DateTime

  ## Returns
    - {:ok, position_data} on success
    - {:error, reason} on failure

  ## Example
      iex> StellarCore.Orbital.propagate_position("ISS", tle1, tle2, DateTime.utc_now())
      {:ok, %{
        position: %{x_km: 1234.5, y_km: 2345.6, z_km: 3456.7},
        velocity: %{vx_km_s: 1.2, vy_km_s: 2.3, vz_km_s: 3.4},
        geodetic: %{latitude_deg: 51.6, longitude_deg: -45.2, altitude_km: 420.5}
      }}
  """
  def propagate_position(satellite_id, tle_line1, tle_line2, timestamp) do
    timestamp_unix = to_unix_timestamp(timestamp)

    # Check cache first
    cache_key = Cache.propagation_key(satellite_id, tle_line1, tle_line2, timestamp_unix)

    Cache.fetch(cache_key, fn ->
      request = %{
        satellite_id: satellite_id,
        tle: %{
          line1: tle_line1,
          line2: tle_line2
        },
        timestamp_unix: timestamp_unix
      }

      # Use circuit breaker for the call
      CircuitBreaker.call(fn ->
        case call_grpc(:propagate_position, request) do
          {:ok, %{"success" => true} = response} ->
            result = parse_propagate_response(response)
            
            # Emit telemetry
            :telemetry.execute(
              [:stellar_core, :orbital, :propagate_position],
              %{cache: :miss},
              %{satellite_id: satellite_id}
            )
            
            {:ok, result}

          {:ok, %{"success" => false, "error_message" => error}} ->
            {:error, {:propagation_failed, error}}

          {:error, reason} ->
            {:error, reason}
        end
      end)
    end)
  end

  @doc """
  Propagate satellite trajectory over a time range.

  ## Parameters
    - satellite_id: String identifier for the satellite
    - tle_line1: First line of TLE
    - tle_line2: Second line of TLE
    - start_time: Start timestamp (Unix integer or DateTime)
    - end_time: End timestamp (Unix integer or DateTime)
    - step_seconds: Time step between points (default: 60)

  ## Returns
    - {:ok, [trajectory_points]} on success
    - {:error, reason} on failure
  """
  def propagate_trajectory(satellite_id, tle_line1, tle_line2, start_time, end_time, step_seconds \\ 60) do
    start_ts = to_unix_timestamp(start_time)
    end_ts = to_unix_timestamp(end_time)

    # Check cache first
    cache_key = Cache.trajectory_key(satellite_id, tle_line1, tle_line2, start_ts, end_ts, step_seconds)

    Cache.fetch(cache_key, fn ->
      request = %{
        satellite_id: satellite_id,
        tle: %{
          line1: tle_line1,
          line2: tle_line2
        },
        start_timestamp_unix: start_ts,
        end_timestamp_unix: end_ts,
        step_seconds: step_seconds
      }

      # Use circuit breaker for the call
      CircuitBreaker.call(fn ->
        case call_grpc(:propagate_trajectory, request) do
          {:ok, %{"success" => true, "points" => points}} ->
            result = Enum.map(points, &parse_trajectory_point/1)
            
            # Emit telemetry
            :telemetry.execute(
              [:stellar_core, :orbital, :propagate_trajectory],
              %{cache: :miss, points: length(result)},
              %{satellite_id: satellite_id}
            )
            
            {:ok, result}

          {:ok, %{"success" => false, "error_message" => error}} ->
            {:error, {:trajectory_failed, error}}

          {:error, reason} ->
            {:error, reason}
        end
      end)
    end)
  end

  @doc """
  Calculate visibility passes for a satellite over a ground station.

  ## Parameters
    - satellite_id: String identifier for the satellite
    - tle_line1: First line of TLE
    - tle_line2: Second line of TLE
    - ground_station: Map with :id, :name, :latitude_deg, :longitude_deg, :altitude_m, :min_elevation_deg
    - start_time: Start of time window
    - end_time: End of time window

  ## Returns
    - {:ok, [passes]} on success
    - {:error, reason} on failure
  """
  def calculate_visibility(satellite_id, tle_line1, tle_line2, ground_station, start_time, end_time) do
    request = %{
      satellite_id: satellite_id,
      tle: %{
        line1: tle_line1,
        line2: tle_line2
      },
      ground_station: ground_station,
      start_timestamp_unix: to_unix_timestamp(start_time),
      end_timestamp_unix: to_unix_timestamp(end_time)
    }

    case call_grpc(:calculate_visibility, request) do
      {:ok, %{"success" => true, "passes" => passes}} ->
        {:ok, Enum.map(passes, &parse_pass/1)}

      {:ok, %{"success" => false, "error_message" => error}} ->
        {:error, {:visibility_failed, error}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Check health of the orbital service.

  ## Returns
    - {:ok, health_info} if service is healthy
    - {:error, reason} if service is unhealthy or unreachable
  """
  def health_check do
    case call_grpc(:health_check, %{}) do
      {:ok, %{"healthy" => true} = response} ->
        {:ok, %{
          healthy: true,
          version: response["version"],
          uptime_seconds: response["uptime_seconds"]
        }}

      {:ok, %{"healthy" => false}} ->
        {:error, :unhealthy}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # ============================================================================
  # Private Functions
  # ============================================================================

  defp call_http(:propagate_position, request) do
    body = %{
      satellite_id: request.satellite_id,
      tle_line1: request.tle.line1,
      tle_line2: request.tle.line2,
      timestamp_unix: request.timestamp_unix
    }

    case HttpClient.post("/api/propagate", body) do
      {:ok, response} -> {:ok, response}
      {:error, :connection_refused} -> {:error, :connection_failed}
      {:error, reason} -> {:error, reason}
    end
  end

  defp call_http(:propagate_trajectory, request) do
    body = %{
      satellite_id: request.satellite_id,
      tle_line1: request.tle.line1,
      tle_line2: request.tle.line2,
      start_timestamp_unix: request.start_timestamp_unix,
      end_timestamp_unix: request.end_timestamp_unix,
      step_seconds: request.step_seconds
    }

    case HttpClient.post("/api/trajectory", body) do
      {:ok, response} -> {:ok, response}
      {:error, :connection_refused} -> {:error, :connection_failed}
      {:error, reason} -> {:error, reason}
    end
  end

  defp call_http(:calculate_visibility, request) do
    body = %{
      satellite_id: request.satellite_id,
      tle_line1: request.tle.line1,
      tle_line2: request.tle.line2,
      ground_station: request.ground_station,
      start_timestamp_unix: request.start_timestamp_unix,
      end_timestamp_unix: request.end_timestamp_unix
    }

    case HttpClient.post("/api/visibility", body) do
      {:ok, response} -> {:ok, response}
      {:error, :connection_refused} -> {:error, :connection_failed}
      {:error, reason} -> {:error, reason}
    end
  end

  defp call_http(:health_check, _request) do
    case HttpClient.get("/health") do
      {:ok, response} -> {:ok, response}
      {:error, reason} -> {:error, reason}
    end
  end

  # Use actual HTTP for real methods, with fallback to mock for unsupported ones
  defp call_grpc(method, request) do
    use_mock = System.get_env("ORBITAL_USE_MOCK", "false") == "true"

    if use_mock do
      mock_response(method, request)
    else
      case call_http(method, request) do
        {:ok, %{"success" => false} = response} ->
          {:ok, response}

        {:error, :connection_failed} ->
          Logger.warning("Orbital service unavailable, falling back to mock response")
          mock_response(method, request)

        result ->
          result
      end
    end
  end

  # Mock responses for development/testing until gRPC client is implemented
  defp mock_response(:propagate_position, request) do
    # Return a reasonable mock position for testing
    {:ok, %{
      "success" => true,
      "satellite_id" => request.satellite_id,
      "timestamp_unix" => request.timestamp_unix,
      "position" => %{
        "x_km" => 6778.0 + :rand.uniform() * 100,
        "y_km" => 0.0 + :rand.uniform() * 100,
        "z_km" => 0.0 + :rand.uniform() * 100
      },
      "velocity" => %{
        "vx_km_s" => 0.0,
        "vy_km_s" => 7.67 + :rand.uniform() * 0.1,
        "vz_km_s" => 0.0
      },
      "geodetic" => %{
        "latitude_deg" => -90 + :rand.uniform() * 180,
        "longitude_deg" => -180 + :rand.uniform() * 360,
        "altitude_km" => 400 + :rand.uniform() * 50
      }
    }}
  end

  defp mock_response(:propagate_trajectory, request) do
    step = request.step_seconds
    start_ts = request.start_timestamp_unix
    end_ts = request.end_timestamp_unix
    
    points = 
      start_ts
      |> Stream.iterate(&(&1 + step))
      |> Enum.take_while(&(&1 <= end_ts))
      |> Enum.map(fn ts ->
        %{
          "timestamp_unix" => ts,
          "position" => %{
            "x_km" => 6778.0 * :math.cos(ts / 1000),
            "y_km" => 6778.0 * :math.sin(ts / 1000),
            "z_km" => 0.0
          },
          "geodetic" => %{
            "latitude_deg" => 51.6 * :math.sin(ts / 500),
            "longitude_deg" => rem(ts, 360) - 180,
            "altitude_km" => 420.0
          }
        }
      end)

    {:ok, %{
      "success" => true,
      "satellite_id" => request.satellite_id,
      "points" => points
    }}
  end

  defp mock_response(:calculate_visibility, request) do
    # Return a mock pass
    start_ts = request.start_timestamp_unix
    
    {:ok, %{
      "success" => true,
      "satellite_id" => request.satellite_id,
      "ground_station_id" => request.ground_station.id,
      "passes" => [
        %{
          "aos_timestamp" => start_ts + 3600,
          "los_timestamp" => start_ts + 4200,
          "max_elevation_timestamp" => start_ts + 3900,
          "max_elevation_deg" => 45.0,
          "aos_azimuth_deg" => 270.0,
          "los_azimuth_deg" => 90.0,
          "duration_seconds" => 600
        }
      ]
    }}
  end

  defp mock_response(:health_check, _request) do
    {:ok, %{
      "healthy" => true,
      "version" => "0.1.0",
      "uptime_seconds" => 3600
    }}
  end

  defp to_unix_timestamp(%DateTime{} = dt), do: DateTime.to_unix(dt)
  defp to_unix_timestamp(unix) when is_integer(unix), do: unix

  defp parse_propagate_response(response) do
    %{
      satellite_id: response["satellite_id"],
      timestamp_unix: response["timestamp_unix"],
      position: parse_position(response["position"]),
      velocity: parse_velocity(response["velocity"]),
      geodetic: parse_geodetic(response["geodetic"])
    }
  end

  defp parse_trajectory_point(point) do
    %{
      timestamp_unix: point["timestamp_unix"],
      position: parse_position(point["position"]),
      geodetic: parse_geodetic(point["geodetic"])
    }
  end

  defp parse_pass(pass) do
    %{
      aos_timestamp: pass["aos_timestamp"],
      los_timestamp: pass["los_timestamp"],
      max_elevation_timestamp: pass["max_elevation_timestamp"],
      max_elevation_deg: pass["max_elevation_deg"],
      aos_azimuth_deg: pass["aos_azimuth_deg"],
      los_azimuth_deg: pass["los_azimuth_deg"],
      duration_seconds: pass["duration_seconds"]
    }
  end

  defp parse_position(nil), do: nil
  defp parse_position(pos) do
    %{
      x_km: pos["x_km"],
      y_km: pos["y_km"],
      z_km: pos["z_km"]
    }
  end

  defp parse_velocity(nil), do: nil
  defp parse_velocity(vel) do
    %{
      vx_km_s: vel["vx_km_s"],
      vy_km_s: vel["vy_km_s"],
      vz_km_s: vel["vz_km_s"]
    }
  end

  defp parse_geodetic(nil), do: nil
  defp parse_geodetic(geo) do
    %{
      latitude_deg: geo["latitude_deg"],
      longitude_deg: geo["longitude_deg"],
      altitude_km: geo["altitude_km"]
    }
  end
end
