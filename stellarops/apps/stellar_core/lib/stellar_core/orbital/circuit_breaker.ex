defmodule StellarCore.Orbital.CircuitBreaker do
  @moduledoc """
  Circuit breaker for orbital service calls.
  
  Uses Fuse to prevent cascading failures when the orbital service
  is unavailable or experiencing issues.
  """

  require Logger

  @fuse_name {:orbital_service, __MODULE__}
  @fuse_opts [
    # Standard fuse options
    {:fuse_strategy, {:standard, 5, 10_000}},
    # Reset after 30 seconds
    {:fuse_refresh, 30_000}
  ]

  @doc """
  Initialize the circuit breaker.
  Called from the application supervisor.
  """
  def start_link(_opts \\ []) do
    :fuse.install(@fuse_name, @fuse_opts)
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
  Execute a function through the circuit breaker.
  
  Returns {:error, :circuit_open} if the circuit is open.
  """
  def call(fun) when is_function(fun, 0) do
    case :fuse.ask(@fuse_name, :sync) do
      :ok ->
        # Circuit is closed, execute function
        try do
          result = fun.()

          case result do
            {:ok, _} ->
              result

            {:error, :connection_refused} ->
              # Melt the fuse on connection errors
              :fuse.melt(@fuse_name)
              result

            {:error, :timeout} ->
              # Melt the fuse on timeouts
              :fuse.melt(@fuse_name)
              result

            {:error, {:http_error, _, _}} ->
              # Melt the fuse on HTTP errors
              :fuse.melt(@fuse_name)
              result

            {:error, _} ->
              # Other errors don't necessarily indicate service issues
              result
          end
        rescue
          error ->
            :fuse.melt(@fuse_name)
            {:error, {:exception, error}}
        end

      :blown ->
        # Circuit is open
        Logger.warning("Circuit breaker is open for orbital service")
        {:error, :circuit_open}

      {:error, :not_found} ->
        # Fuse not installed, execute without protection
        Logger.warning("Circuit breaker not found, executing without protection")
        fun.()
    end
  end

  @doc """
  Get the current circuit breaker status.
  """
  def status do
    case :fuse.ask(@fuse_name, :sync) do
      :ok -> :closed
      :blown -> :open
      {:error, :not_found} -> :not_found
    end
  end

  @doc """
  Manually reset the circuit breaker.
  """
  def reset do
    :fuse.reset(@fuse_name)
  end
end
