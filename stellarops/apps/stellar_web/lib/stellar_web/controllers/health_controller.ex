defmodule StellarWeb.HealthController do
  @moduledoc """
  Health check endpoints for the API.
  
  Provides multiple health check endpoints for different use cases:
  - `/health` - Basic liveness check
  - `/health/ready` - Readiness check (dependencies verified)
  - `/health/live` - Kubernetes liveness probe
  - `/health/detailed` - Detailed component health
  """

  use Phoenix.Controller, formats: [:json]

  @doc """
  GET /health

  Returns the health status of the API and satellite count.
  Basic liveness check for load balancers and simple health monitoring.
  """
  def index(conn, _params) do
    satellite_count = safe_satellite_count()

    json(conn, %{
      status: "ok",
      service: "stellar_web",
      satellite_count: satellite_count,
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
    })
  end

  @doc """
  GET /health/ready

  Readiness probe for Kubernetes and orchestrators.
  Checks that all critical dependencies are available.
  """
  def ready(conn, _params) do
    checks = %{
      database: check_database(),
      satellite_supervisor: check_satellite_supervisor(),
      orbital_service: check_orbital_service()
    }

    all_healthy = Enum.all?(checks, fn {_, status} -> status.healthy end)

    status_code = if all_healthy, do: 200, else: 503

    conn
    |> put_status(status_code)
    |> json(%{
      status: if(all_healthy, do: "ready", else: "not_ready"),
      checks: checks,
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
    })
  end

  @doc """
  GET /health/live

  Kubernetes liveness probe.
  Simple check that the application is running.
  """
  def live(conn, _params) do
    json(conn, %{
      status: "alive",
      service: "stellar_web",
      node: node() |> to_string(),
      uptime_seconds: get_uptime_seconds(),
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
    })
  end

  @doc """
  GET /health/detailed

  Detailed health check with all component statuses.
  For debugging and monitoring dashboards.
  """
  def detailed(conn, _params) do
    memory_info = :erlang.memory()
    system_info = get_system_info()

    checks = %{
      database: check_database(),
      satellite_supervisor: check_satellite_supervisor(),
      orbital_service: check_orbital_service(),
      pubsub: check_pubsub(),
      tle_service: check_tle_service()
    }

    ssa_health = safe_ssa_health()

    all_healthy = Enum.all?(checks, fn {_, status} -> status.healthy end)
    status_code = if all_healthy, do: 200, else: 503

    conn
    |> put_status(status_code)
    |> json(%{
      status: if(all_healthy, do: "healthy", else: "degraded"),
      service: "stellar_web",
      version: get_app_version(),
      node: node() |> to_string(),
      uptime_seconds: get_uptime_seconds(),
      checks: checks,
      ssa: ssa_health,
      satellites: %{
        count: safe_satellite_count(),
        active: safe_active_satellite_count()
      },
      system: system_info,
      memory: %{
        total_mb: div(memory_info[:total], 1_048_576),
        processes_mb: div(memory_info[:processes], 1_048_576),
        ets_mb: div(memory_info[:ets], 1_048_576)
      },
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
    })
  end

  # ============================================================================
  # Health Check Functions
  # ============================================================================

  defp check_database do
    start_time = System.monotonic_time(:millisecond)

    result =
      try do
        StellarData.Repo.query!("SELECT 1")
        :ok
      rescue
        e -> {:error, Exception.message(e)}
      end

    latency = System.monotonic_time(:millisecond) - start_time

    case result do
      :ok ->
        %{healthy: true, latency_ms: latency}

      {:error, message} ->
        %{healthy: false, error: message, latency_ms: latency}
    end
  end

  defp check_satellite_supervisor do
    try do
      satellites = StellarCore.Satellite.Supervisor.list_satellites()
      %{healthy: true, satellite_count: length(satellites)}
    rescue
      _ -> %{healthy: false, error: "Supervisor not available"}
    end
  end

  defp check_orbital_service do
    start_time = System.monotonic_time(:millisecond)

    result =
      try do
        case StellarCore.Orbital.Client.health_check() do
          {:ok, _} -> :ok
          {:error, reason} -> {:error, to_string(reason)}
        end
      rescue
        _ -> {:error, "Service unavailable"}
      end

    latency = System.monotonic_time(:millisecond) - start_time

    case result do
      :ok ->
        %{healthy: true, latency_ms: latency}

      {:error, message} ->
        %{healthy: false, error: message, latency_ms: latency}
    end
  end

  defp check_pubsub do
    try do
      Phoenix.PubSub.node_name(StellarWeb.PubSub)
      %{healthy: true}
    rescue
      _ -> %{healthy: false, error: "PubSub not available"}
    end
  end

  defp check_tle_service do
    try do
      case Process.whereis(StellarCore.TLE.TLEService) do
        nil -> %{healthy: false, error: "TLE service not running"}
        _pid -> %{healthy: true}
      end
    rescue
      _ -> %{healthy: false, error: "Check failed"}
    end
  end

  # ============================================================================
  # Helper Functions
  # ============================================================================

  defp safe_satellite_count do
    try do
      StellarCore.Satellite.count()
    rescue
      _ -> 0
    end
  end

  defp safe_active_satellite_count do
    try do
      length(StellarCore.Satellite.Supervisor.list_satellites())
    rescue
      _ -> 0
    end
  end

  defp safe_ssa_health do
    try do
      StellarData.SSA.get_health_status()
    rescue
      _ -> %{status: :unknown}
    end
  end

  defp get_uptime_seconds do
    {uptime_ms, _} = :erlang.statistics(:wall_clock)
    div(uptime_ms, 1000)
  end

  defp get_app_version do
    case :application.get_key(:stellar_web, :vsn) do
      {:ok, version} -> to_string(version)
      _ -> "unknown"
    end
  end

  defp get_system_info do
    %{
      schedulers: :erlang.system_info(:schedulers_online),
      process_count: :erlang.system_info(:process_count),
      process_limit: :erlang.system_info(:process_limit),
      port_count: :erlang.system_info(:port_count),
      otp_release: :erlang.system_info(:otp_release) |> to_string()
    }
  end
end
