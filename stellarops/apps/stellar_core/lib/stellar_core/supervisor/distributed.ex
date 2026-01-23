defmodule StellarCore.Supervisor.Distributed do
  @moduledoc """
  Distributed supervisor for satellite processes using Horde.
  
  Distributes satellite processes across the cluster and handles
  automatic redistribution when nodes join or leave.
  
  ## Features
  
  - Automatic process distribution
  - Failover to surviving nodes
  - Graceful handoff during rolling deployments
  - Integration with distributed registry
  """
  
  use Horde.DynamicSupervisor
  
  require Logger
  
  @supervisor_name __MODULE__
  
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, @supervisor_name)
    
    Horde.DynamicSupervisor.start_link(
      name: name,
      strategy: :one_for_one,
      members: get_members(),
      distribution_strategy: Horde.UniformDistribution
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
  Start a satellite process in the distributed supervisor.
  
  The process will be started on one of the cluster nodes
  based on the distribution strategy.
  """
  def start_satellite(satellite_id, opts \\ []) do
    child_spec = {
      StellarCore.Satellite.Server,
      Keyword.merge(opts, [satellite_id: satellite_id])
    }
    
    case Horde.DynamicSupervisor.start_child(@supervisor_name, child_spec) do
      {:ok, pid} ->
        Logger.info("Started satellite #{satellite_id} on #{node(pid)}")
        {:ok, pid}
        
      {:error, {:already_started, pid}} ->
        {:ok, pid}
        
      error ->
        Logger.error("Failed to start satellite #{satellite_id}: #{inspect(error)}")
        error
    end
  end
  
  @doc """
  Stop a satellite process.
  """
  def stop_satellite(satellite_id) do
    case StellarCore.Registry.Distributed.lookup(satellite_id) do
      {:ok, pid} ->
        Horde.DynamicSupervisor.terminate_child(@supervisor_name, pid)
        
      {:error, :not_found} ->
        {:error, :not_found}
    end
  end
  
  @doc """
  List all children across the cluster.
  """
  def which_children do
    Horde.DynamicSupervisor.which_children(@supervisor_name)
  end
  
  @doc """
  Count children across the cluster.
  """
  def count_children do
    Horde.DynamicSupervisor.count_children(@supervisor_name)
  end
  
  @doc """
  Update cluster members when nodes join/leave.
  """
  def set_members(members) do
    Horde.DynamicSupervisor.set_members(@supervisor_name, members)
  end
  
  @doc """
  Gracefully redistribute processes (useful for rolling deployments).
  """
  def redistribute do
    # Trigger Horde to redistribute processes
    members = get_members()
    set_members(members)
    Logger.info("Redistributing processes across #{length(members)} nodes")
    :ok
  end
  
  # Get current cluster members
  defp get_members do
    [Node.self() | Node.list()]
    |> Enum.map(fn node -> {__MODULE__, node} end)
  end
end
