defmodule StellarCore.Registry.Distributed do
  @moduledoc """
  Distributed registry for satellite processes using Horde.
  
  Provides cluster-wide process registration and discovery,
  ensuring satellites are accessible from any node in the cluster.
  
  ## Features
  
  - Automatic process distribution across nodes
  - Seamless failover when nodes leave
  - Conflict resolution for duplicate registrations
  - Integration with existing Satellite.Registry
  
  ## Usage
  
      # Register a satellite (usually done by Supervisor)
      {:ok, pid} = DistributedRegistry.register_satellite("SAT-001", SatelliteServer, args)
      
      # Lookup satellite on any node
      {:ok, pid} = DistributedRegistry.lookup("SAT-001")
      
      # List all satellites in cluster
      satellites = DistributedRegistry.list_satellites()
  """
  
  use Horde.Registry
  
  require Logger
  
  @registry_name __MODULE__
  
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, @registry_name)
    
    Horde.Registry.start_link(
      name: name,
      keys: :unique,
      members: get_members()
    )
  end
  
  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]},
      type: :supervisor
    }
  end
  
  @doc """
  Register a satellite process in the distributed registry.
  """
  def register_satellite(satellite_id, pid) when is_pid(pid) do
    Horde.Registry.register(@registry_name, {:satellite, satellite_id}, pid)
  end
  
  @doc """
  Lookup a satellite by ID across the cluster.
  """
  def lookup(satellite_id) do
    case Horde.Registry.lookup(@registry_name, {:satellite, satellite_id}) do
      [{pid, _}] -> {:ok, pid}
      [] -> {:error, :not_found}
    end
  end
  
  @doc """
  Lookup with metadata.
  """
  def lookup_with_meta(satellite_id) do
    case Horde.Registry.lookup(@registry_name, {:satellite, satellite_id}) do
      [{pid, meta}] -> {:ok, {pid, meta}}
      [] -> {:error, :not_found}
    end
  end
  
  @doc """
  List all registered satellites across the cluster.
  """
  def list_satellites do
    Horde.Registry.select(@registry_name, [
      {{{:satellite, :"$1"}, :"$2", :"$3"}, [], [{{:"$1", :"$2"}}]}
    ])
  end
  
  @doc """
  Count total satellites in the cluster.
  """
  def count_satellites do
    Horde.Registry.count(@registry_name)
  end
  
  @doc """
  Unregister a satellite.
  """
  def unregister(satellite_id) do
    Horde.Registry.unregister(@registry_name, {:satellite, satellite_id})
  end
  
  @doc """
  Update the cluster members (called when nodes join/leave).
  """
  def set_members(members) do
    Horde.Registry.set_members(@registry_name, members)
  end
  
  @doc """
  Register for a specific key pattern via PubSub-like dispatch.
  """
  def register_name({:via, _, {_, name}}, pid) do
    Horde.Registry.register(@registry_name, name, pid)
  end
  
  @doc """
  Whereis for :via tuple support.
  """
  def whereis_name({:via, _, {_, name}}) do
    case Horde.Registry.lookup(@registry_name, name) do
      [{pid, _}] -> pid
      [] -> :undefined
    end
  end
  
  # Get initial cluster members
  defp get_members do
    [Node.self() | Node.list()]
    |> Enum.map(fn node -> {__MODULE__, node} end)
  end
end
