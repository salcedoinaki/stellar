defmodule StellarCore.Logger do
  @moduledoc """
  Structured logging utilities for StellarOps.
  
  Provides consistent, structured logging with domain-specific metadata
  for satellite operations, SSA events, and system monitoring.
  
  ## Usage
  
      StellarCore.Logger.info(:satellite, "Satellite mode changed",
        satellite_id: "sat-123",
        old_mode: :nominal,
        new_mode: :safe
      )
  
      StellarCore.Logger.warn(:ssa, "High severity conjunction detected",
        conjunction_id: "conj-456",
        severity: :high,
        miss_distance_km: 0.5
      )
  """

  require Logger

  @type domain :: :satellite | :ssa | :mission | :command | :telemetry | :system | :api
  @type log_level :: :debug | :info | :warning | :error

  # ============================================================================
  # Domain-Specific Logging Functions
  # ============================================================================

  @doc """
  Logs a debug message with structured metadata.
  """
  def debug(domain, message, metadata \\ []) when is_atom(domain) do
    Logger.debug(message, build_metadata(domain, metadata))
  end

  @doc """
  Logs an info message with structured metadata.
  """
  def info(domain, message, metadata \\ []) when is_atom(domain) do
    Logger.info(message, build_metadata(domain, metadata))
  end

  @doc """
  Logs a warning message with structured metadata.
  """
  def warn(domain, message, metadata \\ []) when is_atom(domain) do
    Logger.warning(message, build_metadata(domain, metadata))
  end

  @doc """
  Logs an error message with structured metadata.
  """
  def error(domain, message, metadata \\ []) when is_atom(domain) do
    Logger.error(message, build_metadata(domain, metadata))
  end

  # ============================================================================
  # Satellite Operations Logging
  # ============================================================================

  @doc """
  Logs a satellite state change event.
  """
  def log_satellite_state_change(satellite_id, field, old_value, new_value) do
    info(:satellite, "Satellite state changed",
      satellite_id: satellite_id,
      field: field,
      old_value: inspect(old_value),
      new_value: inspect(new_value)
    )
  end

  @doc """
  Logs a satellite command execution.
  """
  def log_command_executed(satellite_id, command_type, command_id, result) do
    level = if result == :success, do: :info, else: :warning

    log(level, :command, "Command executed",
      satellite_id: satellite_id,
      command_type: command_type,
      command_id: command_id,
      result: result
    )
  end

  @doc """
  Logs a satellite telemetry anomaly.
  """
  def log_telemetry_anomaly(satellite_id, anomaly_type, details) do
    warn(:telemetry, "Telemetry anomaly detected",
      satellite_id: satellite_id,
      anomaly_type: anomaly_type,
      details: inspect(details)
    )
  end

  # ============================================================================
  # SSA Logging
  # ============================================================================

  @doc """
  Logs a conjunction detection event.
  """
  def log_conjunction_detected(conjunction_id, severity, primary_id, secondary_id, tca) do
    level = if severity in [:critical, :high], do: :warning, else: :info

    log(level, :ssa, "Conjunction detected",
      conjunction_id: conjunction_id,
      severity: severity,
      primary_object_id: primary_id,
      secondary_object_id: secondary_id,
      tca: DateTime.to_iso8601(tca)
    )
  end

  @doc """
  Logs a COA generation event.
  """
  def log_coa_generated(coa_id, conjunction_id, maneuver_type, delta_v) do
    info(:ssa, "COA generated",
      coa_id: coa_id,
      conjunction_id: conjunction_id,
      maneuver_type: maneuver_type,
      delta_v_m_s: delta_v
    )
  end

  @doc """
  Logs a COA decision event.
  """
  def log_coa_decision(coa_id, decision, decided_by) do
    level = if decision == :rejected, do: :warning, else: :info

    log(level, :ssa, "COA decision made",
      coa_id: coa_id,
      decision: decision,
      decided_by: decided_by
    )
  end

  @doc """
  Logs a screening run completion.
  """
  def log_screening_complete(objects_processed, conjunctions_found, duration_ms) do
    info(:ssa, "Screening run completed",
      objects_processed: objects_processed,
      conjunctions_found: conjunctions_found,
      duration_ms: duration_ms
    )
  end

  # ============================================================================
  # Mission Logging
  # ============================================================================

  @doc """
  Logs a mission status change.
  """
  def log_mission_status_change(mission_id, satellite_id, old_status, new_status) do
    info(:mission, "Mission status changed",
      mission_id: mission_id,
      satellite_id: satellite_id,
      old_status: old_status,
      new_status: new_status
    )
  end

  @doc """
  Logs a mission completion.
  """
  def log_mission_completed(mission_id, satellite_id, success, duration_seconds) do
    level = if success, do: :info, else: :warning

    log(level, :mission, "Mission completed",
      mission_id: mission_id,
      satellite_id: satellite_id,
      success: success,
      duration_seconds: duration_seconds
    )
  end

  # ============================================================================
  # System Logging
  # ============================================================================

  @doc """
  Logs a service startup event.
  """
  def log_service_started(service_name, config \\ %{}) do
    info(:system, "Service started",
      service: service_name,
      config: inspect(config)
    )
  end

  @doc """
  Logs a service shutdown event.
  """
  def log_service_stopped(service_name, reason) do
    info(:system, "Service stopped",
      service: service_name,
      reason: inspect(reason)
    )
  end

  @doc """
  Logs a database connection event.
  """
  def log_db_connection(pool_name, status, connections) do
    info(:system, "Database connection status",
      pool: pool_name,
      status: status,
      connections: connections
    )
  end

  @doc """
  Logs an external API call.
  """
  def log_external_api_call(service, endpoint, status, duration_ms) do
    level = if status in [:ok, 200, 201, 204], do: :debug, else: :warning

    log(level, :api, "External API call",
      service: service,
      endpoint: endpoint,
      status: status,
      duration_ms: duration_ms
    )
  end

  # ============================================================================
  # Private Helpers
  # ============================================================================

  defp log(:debug, domain, message, metadata), do: debug(domain, message, metadata)
  defp log(:info, domain, message, metadata), do: info(domain, message, metadata)
  defp log(:warning, domain, message, metadata), do: warn(domain, message, metadata)
  defp log(:error, domain, message, metadata), do: error(domain, message, metadata)

  defp build_metadata(domain, metadata) do
    base = [
      domain: domain,
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
    ]

    Keyword.merge(base, metadata)
  end
end
