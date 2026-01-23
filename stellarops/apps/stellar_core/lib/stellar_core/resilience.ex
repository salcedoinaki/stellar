defmodule StellarCore.Resilience do
  @moduledoc """
  Resilience patterns and graceful degradation strategies for StellarOps.
  
  Provides:
  - Fallback behaviors when services are unavailable
  - Graceful degradation strategies
  - Health check aggregation
  - Service dependency tracking
  
  ## Degradation Modes
  
  The system operates in different modes based on service availability:
  
  - **Full**: All services operational
  - **Degraded**: Some services unavailable, using cached data
  - **Critical**: Core services unavailable, read-only mode
  - **Emergency**: Minimal functionality, alarms only
  """
  
  require Logger
  
  alias StellarCore.CircuitBreakers
  
  @services [:orbital_service, :tle_celestrak, :tle_spacetrack, :intel_feed]
  
  @doc """
  Get the current system operational mode based on circuit breaker states.
  """
  def operational_mode do
    statuses = CircuitBreakers.status_all()
    open_count = Enum.count(statuses, fn {_, status} -> status == :open end)
    
    cond do
      open_count == 0 ->
        :full
        
      statuses[:orbital_service] == :open ->
        :critical
        
      open_count == 1 ->
        :degraded
        
      open_count >= 2 ->
        :critical
        
      true ->
        :degraded
    end
  end
  
  @doc """
  Check if the system is healthy enough to perform a specific operation.
  """
  def can_perform?(operation) do
    mode = operational_mode()
    
    case {operation, mode} do
      # Always allowed
      {:read_alarms, _} -> true
      {:acknowledge_alarm, _} -> true
      
      # Require at least degraded mode
      {:read_satellites, mode} when mode in [:full, :degraded] -> true
      {:read_conjunctions, mode} when mode in [:full, :degraded] -> true
      
      # Require full operational mode
      {:create_mission, :full} -> true
      {:execute_coa, :full} -> true
      {:propagate_position, :full} -> true
      
      # Degraded mode with fallback
      {:propagate_position, :degraded} -> :fallback_to_cache
      {:get_conjunction, :degraded} -> :fallback_to_cache
      
      # Not allowed
      _ -> false
    end
  end
  
  @doc """
  Execute an operation with graceful degradation.
  
  If the primary operation fails, attempts fallback strategies.
  """
  def with_fallback(operation, primary_fn, opts \\ []) do
    fallback_fn = Keyword.get(opts, :fallback)
    cache_key = Keyword.get(opts, :cache_key)
    
    case primary_fn.() do
      {:ok, result} = success ->
        # Cache successful result if cache key provided
        if cache_key, do: cache_result(cache_key, result)
        success
        
      {:error, :circuit_open} ->
        handle_degraded(operation, fallback_fn, cache_key)
        
      {:error, :timeout} ->
        handle_degraded(operation, fallback_fn, cache_key)
        
      {:error, _} = error ->
        if fallback_fn do
          Logger.warning("Primary operation failed, trying fallback for #{operation}")
          fallback_fn.()
        else
          error
        end
    end
  end
  
  @doc """
  Get system health summary for monitoring.
  """
  def health_summary do
    circuit_status = CircuitBreakers.status_all()
    mode = operational_mode()
    
    %{
      mode: mode,
      healthy: mode == :full,
      timestamp: DateTime.utc_now(),
      services: Enum.map(circuit_status, fn {name, status} ->
        %{
          name: name,
          status: status,
          healthy: status == :closed
        }
      end),
      summary: %{
        total: map_size(circuit_status),
        healthy: Enum.count(circuit_status, fn {_, s} -> s == :closed end),
        unhealthy: Enum.count(circuit_status, fn {_, s} -> s == :open end)
      }
    }
  end
  
  @doc """
  Record a service failure for tracking and alerting.
  """
  def record_failure(service, error, context \\ %{}) do
    Logger.error("Service failure: #{service} - #{inspect(error)}", context)
    
    :telemetry.execute(
      [:stellar, :resilience, :failure],
      %{},
      %{service: service, error: error, context: context}
    )
    
    # Check if we should raise an alarm
    if should_alert?(service) do
      StellarCore.Alarms.raise_alarm(
        :"#{service}_failure",
        "Service #{service} is experiencing failures",
        :warning,
        "resilience",
        Map.merge(context, %{service: service, error: inspect(error)})
      )
    end
  end
  
  @doc """
  List available fallback strategies for a service.
  """
  def fallback_strategies(service) do
    case service do
      :orbital_service ->
        [
          :use_cached_position,
          :use_last_known_position,
          :skip_propagation
        ]
        
      :tle_celestrak ->
        [
          :use_spacetrack,
          :use_cached_tle,
          :skip_update
        ]
        
      :tle_spacetrack ->
        [
          :use_celestrak,
          :use_cached_tle,
          :skip_update
        ]
        
      :intel_feed ->
        [
          :use_cached_intel,
          :skip_update
        ]
        
      _ ->
        [:skip]
    end
  end
  
  # Private functions
  
  defp handle_degraded(operation, fallback_fn, cache_key) do
    Logger.warning("Operation #{operation} degraded, attempting fallback")
    
    cond do
      cache_key && cached = get_cached(cache_key) ->
        Logger.info("Using cached result for #{operation}")
        {:ok, cached}
        
      fallback_fn ->
        Logger.info("Executing fallback for #{operation}")
        fallback_fn.()
        
      true ->
        {:error, :service_unavailable}
    end
  end
  
  defp cache_result(key, result) do
    # Use Cachex for caching
    Cachex.put(:stellar_resilience_cache, key, result, ttl: :timer.minutes(15))
  end
  
  defp get_cached(key) do
    case Cachex.get(:stellar_resilience_cache, key) do
      {:ok, value} -> value
      _ -> nil
    end
  end
  
  defp should_alert?(service) do
    # Only alert once per 5 minutes per service
    key = {:alert_throttle, service}
    now = System.monotonic_time(:second)
    
    case :persistent_term.get(key, nil) do
      nil ->
        :persistent_term.put(key, now)
        true
        
      last_alert when now - last_alert > 300 ->
        :persistent_term.put(key, now)
        true
        
      _ ->
        false
    end
  end
end
