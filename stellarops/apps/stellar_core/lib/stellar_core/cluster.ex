defmodule StellarCore.Cluster do
  @moduledoc """
  Elixir clustering configuration for StellarOps.
  
  Uses libcluster with DNS-based discovery for Kubernetes deployments.
  Supports multiple topologies for different environments.
  
  ## Topologies
  
  - **Kubernetes DNS**: Uses DNS SRV records from headless service
  - **Gossip**: For development/local clustering
  - **EPMD**: Traditional Erlang clustering
  
  ## Configuration
  
  Set the following environment variables:
  
  - `RELEASE_NODE`: Node name (e.g., `backend@10.0.0.1`)
  - `RELEASE_COOKIE`: Erlang cookie for authentication
  - `CLUSTER_ENABLED`: Enable/disable clustering (default: true in prod)
  - `CLUSTER_TOPOLOGY`: Topology to use (kubernetes_dns, gossip, epmd)
  - `KUBERNETES_NAMESPACE`: K8s namespace for DNS discovery
  - `KUBERNETES_SERVICE_NAME`: Headless service name
  """
  
  require Logger
  
  @doc """
  Get the libcluster topology configuration.
  """
  def topology do
    case cluster_topology() do
      :kubernetes_dns -> kubernetes_dns_topology()
      :gossip -> gossip_topology()
      :epmd -> epmd_topology()
      :disabled -> []
      _ -> []
    end
  end
  
  @doc """
  Check if clustering is enabled.
  """
  def enabled? do
    System.get_env("CLUSTER_ENABLED", "true") == "true" and
      Mix.env() == :prod
  end
  
  @doc """
  Get the current cluster topology type.
  """
  def cluster_topology do
    case System.get_env("CLUSTER_TOPOLOGY", "kubernetes_dns") do
      "kubernetes_dns" -> :kubernetes_dns
      "gossip" -> :gossip
      "epmd" -> :epmd
      "disabled" -> :disabled
      other ->
        Logger.warning("Unknown cluster topology: #{other}, defaulting to disabled")
        :disabled
    end
  end
  
  @doc """
  List all connected nodes.
  """
  def nodes do
    [Node.self() | Node.list()]
  end
  
  @doc """
  Check cluster health.
  """
  def health do
    connected = Node.list()
    
    %{
      self: Node.self(),
      connected_nodes: connected,
      node_count: length(connected) + 1,
      topology: cluster_topology(),
      status: if(length(connected) > 0, do: :connected, else: :isolated)
    }
  end
  
  # Kubernetes DNS topology using headless service
  defp kubernetes_dns_topology do
    namespace = System.get_env("KUBERNETES_NAMESPACE", "stellarops")
    service = System.get_env("KUBERNETES_SERVICE_NAME", "backend-headless")
    app_name = System.get_env("RELEASE_NAME", "stellarops")
    
    [
      stellar_cluster: [
        strategy: Cluster.Strategy.Kubernetes.DNS,
        config: [
          service: service,
          application_name: app_name,
          namespace: namespace,
          polling_interval: 5_000
        ]
      ]
    ]
  end
  
  # Gossip topology for development
  defp gossip_topology do
    [
      stellar_cluster: [
        strategy: Cluster.Strategy.Gossip,
        config: [
          port: String.to_integer(System.get_env("GOSSIP_PORT", "45892")),
          if_addr: System.get_env("GOSSIP_IF_ADDR", "0.0.0.0"),
          multicast_addr: System.get_env("GOSSIP_MULTICAST_ADDR", "230.1.1.251"),
          multicast_ttl: 1,
          secret: System.get_env("GOSSIP_SECRET", "stellarops-dev")
        ]
      ]
    ]
  end
  
  # EPMD topology for explicit node list
  defp epmd_topology do
    hosts = 
      System.get_env("CLUSTER_NODES", "")
      |> String.split(",")
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))
      |> Enum.map(&String.to_atom/1)
    
    [
      stellar_cluster: [
        strategy: Cluster.Strategy.Epmd,
        config: [
          hosts: hosts
        ]
      ]
    ]
  end
end
