defmodule StellarCore.CircuitBreakers do
  @moduledoc """
  Central circuit breaker registry and management.
  
  Manages circuit breakers for all external service calls:
  - Orbital service (SGP4 propagation)
  - TLE ingestion (CelesTrak, Space-Track)
  - Intel ingestion (threat intelligence feeds)
  
  Uses the Fuse library to prevent cascading failures.
  
  ## Usage
  
      # Execute with circuit breaker protection
      CircuitBreakers.call(:tle_celestrak, fn ->
        CelesTrakClient.fetch(:active)
      end)
      
      # Check status
      CircuitBreakers.status(:tle_celestrak)
      
      # Reset manually (e.g., after fixing an issue)
      CircuitBreakers.reset(:tle_celestrak)
  """
  
  require Logger
  
  # Circuit breaker configurations
  @breakers %{
    # Orbital service - critical, allow some failures before tripping
    orbital_service: [
      fuse_strategy: {:standard, 5, 10_000},  # 5 failures in 10 seconds
      fuse_refresh: 30_000,                    # Reset after 30 seconds
      fallback: :cached_or_error
    ],
    # CelesTrak API - external, more tolerant
    tle_celestrak: [
      fuse_strategy: {:standard, 3, 30_000},  # 3 failures in 30 seconds
      fuse_refresh: 60_000,                    # Reset after 1 minute
      fallback: :skip
    ],
    # Space-Track API - external, authenticated
    tle_spacetrack: [
      fuse_strategy: {:standard, 3, 30_000},
      fuse_refresh: 120_000,                   # Reset after 2 minutes
      fallback: :skip
    ],
    # Intel ingestion - external feeds
    intel_feed: [
      fuse_strategy: {:standard, 3, 60_000},  # 3 failures in 1 minute
      fuse_refresh: 300_000,                   # Reset after 5 minutes
      fallback: :skip
    ]
  }
  
  @doc """
  Initialize all circuit breakers.
  Called from the application supervisor.
  """
  def start_link(_opts \\ []) do
    install_all()
    :ignore
  end
  
  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]},
      type: :worker,
      restart: :temporary
    }
  end
  
  @doc """
  Install all configured circuit breakers.
  """
  def install_all do
    Enum.each(@breakers, fn {name, config} ->
      fuse_name = {:circuit_breaker, name}
      fuse_opts = [
        {:fuse_strategy, Keyword.get(config, :fuse_strategy)},
        {:fuse_refresh, Keyword.get(config, :fuse_refresh)}
      ]
      
      :fuse.install(fuse_name, fuse_opts)
      Logger.debug("Installed circuit breaker: #{name}")
    end)
  end
  
  @doc """
  Execute a function through a named circuit breaker.
  
  ## Options
  - `:fallback` - Custom fallback function or value when circuit is open
  - `:on_open` - Callback when circuit opens
  
  ## Returns
  - `{:ok, result}` on success
  - `{:error, :circuit_open}` when circuit is open
  - `{:error, reason}` on other failures
  """
  def call(breaker_name, fun, opts \\ []) when is_atom(breaker_name) and is_function(fun, 0) do
    fuse_name = {:circuit_breaker, breaker_name}
    
    case :fuse.ask(fuse_name, :sync) do
      :ok ->
        execute_with_tracking(breaker_name, fuse_name, fun)
        
      :blown ->
        handle_circuit_open(breaker_name, opts)
        
      {:error, :not_found} ->
        Logger.warning("Circuit breaker #{breaker_name} not found, executing without protection")
        execute_unprotected(fun)
    end
  end
  
  @doc """
  Get the current status of a circuit breaker.
  
  Returns `:closed`, `:open`, or `:not_found`
  """
  def status(breaker_name) do
    fuse_name = {:circuit_breaker, breaker_name}
    
    case :fuse.ask(fuse_name, :sync) do
      :ok -> :closed
      :blown -> :open
      {:error, :not_found} -> :not_found
    end
  end
  
  @doc """
  Get status of all circuit breakers.
  """
  def status_all do
    @breakers
    |> Map.keys()
    |> Enum.map(fn name -> {name, status(name)} end)
    |> Map.new()
  end
  
  @doc """
  Manually reset a circuit breaker.
  """
  def reset(breaker_name) do
    fuse_name = {:circuit_breaker, breaker_name}
    :fuse.reset(fuse_name)
    Logger.info("Circuit breaker #{breaker_name} manually reset")
    :ok
  end
  
  @doc """
  Reset all circuit breakers.
  """
  def reset_all do
    Enum.each(Map.keys(@breakers), &reset/1)
    :ok
  end
  
  @doc """
  Manually melt (trip) a circuit breaker.
  Useful for testing or when you know a service is down.
  """
  def melt(breaker_name) do
    fuse_name = {:circuit_breaker, breaker_name}
    :fuse.melt(fuse_name)
    Logger.info("Circuit breaker #{breaker_name} manually melted")
    :ok
  end
  
  @doc """
  Get configuration for a circuit breaker.
  """
  def get_config(breaker_name) do
    Map.get(@breakers, breaker_name)
  end
  
  @doc """
  List all configured circuit breakers.
  """
  def list_breakers do
    Map.keys(@breakers)
  end
  
  # Private functions
  
  defp execute_with_tracking(breaker_name, fuse_name, fun) do
    start_time = System.monotonic_time(:microsecond)
    
    try do
      result = fun.()
      duration = System.monotonic_time(:microsecond) - start_time
      
      # Emit telemetry
      :telemetry.execute(
        [:stellar, :circuit_breaker, :call],
        %{duration: duration},
        %{breaker: breaker_name, status: :success}
      )
      
      case result do
        {:ok, _} = success ->
          success
          
        {:error, :connection_refused} = error ->
          :fuse.melt(fuse_name)
          emit_melt_telemetry(breaker_name, :connection_refused)
          error
          
        {:error, :timeout} = error ->
          :fuse.melt(fuse_name)
          emit_melt_telemetry(breaker_name, :timeout)
          error
          
        {:error, {:http_error, status, _}} = error when status >= 500 ->
          :fuse.melt(fuse_name)
          emit_melt_telemetry(breaker_name, :server_error)
          error
          
        {:error, _} = error ->
          # Don't melt for client errors or business logic errors
          error
          
        other ->
          # Non-standard return, treat as success
          {:ok, other}
      end
    rescue
      error ->
        duration = System.monotonic_time(:microsecond) - start_time
        :fuse.melt(fuse_name)
        
        :telemetry.execute(
          [:stellar, :circuit_breaker, :call],
          %{duration: duration},
          %{breaker: breaker_name, status: :exception}
        )
        
        Logger.error("Circuit breaker #{breaker_name} caught exception: #{inspect(error)}")
        {:error, {:exception, error}}
    end
  end
  
  defp execute_unprotected(fun) do
    try do
      case fun.() do
        {:ok, _} = result -> result
        {:error, _} = error -> error
        other -> {:ok, other}
      end
    rescue
      error -> {:error, {:exception, error}}
    end
  end
  
  defp handle_circuit_open(breaker_name, opts) do
    Logger.warning("Circuit breaker #{breaker_name} is open, request blocked")
    
    :telemetry.execute(
      [:stellar, :circuit_breaker, :blocked],
      %{},
      %{breaker: breaker_name}
    )
    
    # Check for custom fallback
    config = get_config(breaker_name) || []
    fallback = Keyword.get(opts, :fallback, Keyword.get(config, :fallback, :error))
    
    case fallback do
      :error ->
        {:error, :circuit_open}
        
      :skip ->
        {:error, :circuit_open}
        
      :cached_or_error ->
        {:error, :circuit_open}
        
      fun when is_function(fun, 0) ->
        fun.()
        
      value ->
        {:ok, value}
    end
  end
  
  defp emit_melt_telemetry(breaker_name, reason) do
    :telemetry.execute(
      [:stellar, :circuit_breaker, :melt],
      %{},
      %{breaker: breaker_name, reason: reason}
    )
    
    Logger.warning("Circuit breaker #{breaker_name} melted due to: #{reason}")
  end
end
