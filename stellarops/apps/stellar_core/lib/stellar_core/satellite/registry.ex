defmodule StellarCore.Satellite.Registry do
  @moduledoc """
  Registry wrapper for satellite processes.

  Provides a centralized way to look up satellite GenServers by their ID.
  Uses Elixir's built-in Registry with `:unique` keys.
  """

  @registry_name __MODULE__

  @doc """
  Returns the registry name for supervision tree configuration.
  """
  def registry_name, do: @registry_name

  @doc """
  Returns a via tuple for registering/looking up a satellite by id.

  ## Examples

      iex> StellarCore.Satellite.Registry.via_tuple("SAT-001")
      {:via, Registry, {StellarCore.Satellite.Registry, "SAT-001"}}
  """
  @spec via_tuple(String.t()) :: {:via, Registry, {__MODULE__, String.t()}}
  def via_tuple(id) when is_binary(id) do
    {:via, Registry, {@registry_name, id}}
  end

  @doc """
  Looks up the PID for a satellite by id.

  Returns `{:ok, pid}` if found, `:error` otherwise.
  """
  @spec lookup(String.t()) :: {:ok, pid()} | :error
  def lookup(id) when is_binary(id) do
    case Registry.lookup(@registry_name, id) do
      [{pid, _value}] -> {:ok, pid}
      [] -> :error
    end
  end

  @doc """
  Returns a list of all registered satellite IDs.
  """
  @spec list_ids() :: [String.t()]
  def list_ids do
    @registry_name
    |> Registry.select([{{:"$1", :_, :_}, [], [:"$1"]}])
  end

  @doc """
  Returns the count of registered satellites.
  """
  @spec count() :: non_neg_integer()
  def count do
    Registry.count(@registry_name)
  end

  @doc """
  Child spec for starting the registry under a supervisor.
  """
  def child_spec(_opts) do
    Registry.child_spec(keys: :unique, name: @registry_name)
  end
end
