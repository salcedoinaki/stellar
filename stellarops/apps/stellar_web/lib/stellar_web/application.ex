defmodule StellarWeb.Application do
  @moduledoc """
  OTP Application for StellarWeb.

  Starts the Phoenix endpoint and PubSub for real-time communication.
  Configures libcluster for distributed Elixir clustering in Kubernetes.
  """

  use Application

  @impl true
  def start(_type, _args) do
    children =
      [
        # Start PromEx for metrics
        StellarWeb.PromEx,
        # Start the PubSub system
        {Phoenix.PubSub, name: StellarWeb.PubSub},
        # Start token revocation list (for JWT logout)
        StellarWeb.Auth.TokenRevocation,
        # Start the Endpoint (http/https)
        StellarWeb.Endpoint
      ]
      |> maybe_add_cluster_supervisor()

    opts = [strategy: :one_for_one, name: StellarWeb.Supervisor]
    Supervisor.start_link(children, opts)
  end

  @impl true
  def config_change(changed, _new, removed) do
    StellarWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  # Conditionally add libcluster supervisor based on config
  defp maybe_add_cluster_supervisor(children) do
    if cluster_enabled?() do
      topologies = cluster_topologies()
      [{Cluster.Supervisor, [topologies, [name: StellarWeb.ClusterSupervisor]]} | children]
    else
      children
    end
  end

  defp cluster_enabled? do
    System.get_env("CLUSTER_ENABLED", "false") == "true"
  end

  defp cluster_topologies do
    strategy = System.get_env("CLUSTER_STRATEGY", "gossip")

    case strategy do
      "kubernetes" ->
        kubernetes_topology()

      "dns" ->
        dns_topology()

      _ ->
        # Default gossip for local development
        gossip_topology()
    end
  end

  defp kubernetes_topology do
    [
      stellarops: [
        strategy: Cluster.Strategy.Kubernetes,
        config: [
          mode: :ip,
          kubernetes_node_basename: System.get_env("RELEASE_NAME", "backend"),
          kubernetes_selector: System.get_env("CLUSTER_KUBERNETES_SELECTOR", "app=backend"),
          kubernetes_namespace: System.get_env("CLUSTER_KUBERNETES_NAMESPACE", "stellarops"),
          polling_interval: 5_000
        ]
      ]
    ]
  end

  defp dns_topology do
    [
      stellarops: [
        strategy: Cluster.Strategy.DNSPoll,
        config: [
          polling_interval: 5_000,
          query: System.get_env("CLUSTER_DNS_QUERY", "backend-headless.stellarops.svc.cluster.local"),
          node_basename: System.get_env("RELEASE_NAME", "backend")
        ]
      ]
    ]
  end

  defp gossip_topology do
    [
      stellarops: [
        strategy: Cluster.Strategy.Gossip,
        config: [
          port: 45892,
          if_addr: "0.0.0.0",
          multicast_if: "0.0.0.0",
          multicast_addr: "230.1.1.251",
          broadcast_only: true
        ]
      ]
    ]
  end
end
