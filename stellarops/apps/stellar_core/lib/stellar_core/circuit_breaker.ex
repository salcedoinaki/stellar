defmodule StellarCore.CircuitBreaker do
  @moduledoc """
  Circuit breaker implementation for external service calls.
  
  Uses the Fuse library to implement circuit breaker patterns for:
  - Orbital service (Rust gRPC/HTTP)
  - TLE ingestion (CelesTrak, Space-Track)
  - Intel ingestion (external APIs)
  
  Circuit states:
  - :ok - Circuit closed, requests allowed
  - :blown - Circuit open, requests rejected (fallback used)
  
  The circuit opens after a configurable number of failures within a time window,
  and automatically resets after a cooldown period.
  """
  
  require Logger
  
  # Circuit breaker names
  @orbital_fuse :orbital_service
  @celestrak_fuse :celestrak_api
  @spacetrack_fuse :spacetrack_api
  @intel_fuse :intel_api
  
  # Default configurations
  @default_opts %{
    # Number of failures before circuit opens
    failure_threshold: 5,
    # Time window for counting failures (ms)
    failure_window: 60_000,
    # Time to wait before resetting (ms)
    reset_timeout: 30_000
  }
  
  # ============================================================================
  # Setup
  # ============================================================================
  
  @doc """
  Initialize all circuit breakers.
  
  Should be called during application startup.
  """
  def init do
    install_fuse(@orbital_fuse, orbital_opts())
    install_fuse(@celestrak_fuse, celestrak_opts())
    install_fuse(@spacetrack_fuse, spacetrack_opts())
    install_fuse(@intel_fuse, intel_opts())
    
    Logger.info("Circuit breakers initialized")
    :ok
  end
  
  defp install_fuse(name, opts) do
    # Fuse options: {{:standard, failure_count, window_ms}, {:reset, reset_ms}}
    fuse_opts = {
      {:standard, opts.failure_threshold, opts.failure_window},
      {:reset, opts.reset_timeout}
    }
    
    :fuse.install(name, fuse_opts)
  end
  
  defp orbital_opts do
    %{
      failure_threshold: get_config(:orbital_failure_threshold, 3),
      failure_window: get_config(:orbital_failure_window, 30_000),
      reset_timeout: get_config(:orbital_reset_timeout, 15_000)
    }
  end
  
  defp celestrak_opts do
    %{
      failure_threshold: get_config(:celestrak_failure_threshold, 5),
      failure_window: get_config(:celestrak_failure_window, 60_000),
      reset_timeout: get_config(:celestrak_reset_timeout, 60_000)
    }
  end
  
  defp spacetrack_opts do
    %{
      failure_threshold: get_config(:spacetrack_failure_threshold, 3),
      failure_window: get_config(:spacetrack_failure_window, 60_000),
      reset_timeout: get_config(:spacetrack_reset_timeout, 120_000)
    }
  end
  
  defp intel_opts do
    %{
      failure_threshold: get_config(:intel_failure_threshold, 5),
      failure_window: get_config(:intel_failure_window, 60_000),
      reset_timeout: get_config(:intel_reset_timeout, 60_000)
    }
  end
  
  defp get_config(key, default) do
    Application.get_env(:stellar_core, :circuit_breaker, [])
    |> Keyword.get(key, default)
  end
  
  # ============================================================================
  # Orbital Service
  # ============================================================================
  
  @doc """
  Execute a call to the orbital service with circuit breaker protection.
  
  Returns {:ok, result} on success, {:error, :circuit_open} if circuit is open,
  or {:error, reason} on failure.
  """
  def call_orbital(fun, fallback \\ nil) when is_function(fun, 0) do
    call_with_breaker(@orbital_fuse, fun, fallback, :orbital)
  end
  
  @doc """
  Check orbital service circuit state.
  """
  def orbital_status do
    get_status(@orbital_fuse)
  end
  
  # ============================================================================
  # CelesTrak API
  # ============================================================================
  
  @doc """
  Execute a call to CelesTrak with circuit breaker protection.
  """
  def call_celestrak(fun, fallback \\ nil) when is_function(fun, 0) do
    call_with_breaker(@celestrak_fuse, fun, fallback, :celestrak)
  end
  
  @doc """
  Check CelesTrak circuit state.
  """
  def celestrak_status do
    get_status(@celestrak_fuse)
  end
  
  # ============================================================================
  # Space-Track API
  # ============================================================================
  
  @doc """
  Execute a call to Space-Track with circuit breaker protection.
  """
  def call_spacetrack(fun, fallback \\ nil) when is_function(fun, 0) do
    call_with_breaker(@spacetrack_fuse, fun, fallback, :spacetrack)
  end
  
  @doc """
  Check Space-Track circuit state.
  """
  def spacetrack_status do
    get_status(@spacetrack_fuse)
  end
  
  # ============================================================================
  # Intel API
  # ============================================================================
  
  @doc """
  Execute a call to intel API with circuit breaker protection.
  """
  def call_intel(fun, fallback \\ nil) when is_function(fun, 0) do
    call_with_breaker(@intel_fuse, fun, fallback, :intel)
  end
  
  @doc """
  Check intel API circuit state.
  """
  def intel_status do
    get_status(@intel_fuse)
  end
  
  # ============================================================================
  # Status & Metrics
  # ============================================================================
  
  @doc """
  Get status of all circuit breakers.
  """
  def all_status do
    %{
      orbital: orbital_status(),
      celestrak: celestrak_status(),
      spacetrack: spacetrack_status(),
      intel: intel_status()
    }
  end
  
  @doc """
  Reset a specific circuit breaker.
  """
  def reset(name) when name in [:orbital, :celestrak, :spacetrack, :intel] do
    fuse_name = case name do
      :orbital -> @orbital_fuse
      :celestrak -> @celestrak_fuse
      :spacetrack -> @spacetrack_fuse
      :intel -> @intel_fuse
    end
    
    :fuse.reset(fuse_name)
    Logger.info("Circuit breaker #{name} manually reset")
    :ok
  end
  
  @doc """
  Reset all circuit breakers.
  """
  def reset_all do
    [:orbital, :celestrak, :spacetrack, :intel]
    |> Enum.each(&reset/1)
    :ok
  end
  
  # ============================================================================
  # Private Functions
  # ============================================================================
  
  defp call_with_breaker(fuse_name, fun, fallback, service_name) do
    case :fuse.ask(fuse_name, :sync) do
      :ok ->
        try do
          result = fun.()
          emit_metric(service_name, :success)
          result
        rescue
          e ->
            :fuse.melt(fuse_name)
            emit_metric(service_name, :failure)
            Logger.warning("Circuit breaker #{service_name} recorded failure: #{inspect(e)}")
            {:error, {:exception, Exception.message(e)}}
        catch
          :exit, reason ->
            :fuse.melt(fuse_name)
            emit_metric(service_name, :failure)
            Logger.warning("Circuit breaker #{service_name} recorded exit: #{inspect(reason)}")
            {:error, {:exit, reason}}
        end
        
      :blown ->
        emit_metric(service_name, :rejected)
        Logger.warning("Circuit breaker #{service_name} is open, rejecting request")
        
        if fallback do
          Logger.info("Using fallback for #{service_name}")
          emit_metric(service_name, :fallback)
          fallback.()
        else
          {:error, :circuit_open}
        end
        
      {:error, :not_found} ->
        # Fuse not installed, run without protection
        Logger.warning("Circuit breaker #{service_name} not installed, running unprotected")
        fun.()
    end
  end
  
  defp get_status(fuse_name) do
    case :fuse.ask(fuse_name, :sync) do
      :ok -> :closed
      :blown -> :open
      {:error, :not_found} -> :not_installed
    end
  end
  
  defp emit_metric(service, outcome) do
    :telemetry.execute(
      [:stellar, :circuit_breaker, outcome],
      %{count: 1},
      %{service: service}
    )
  end
end
