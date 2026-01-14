# StellarOps Kubernetes Deployment

This directory contains Kubernetes manifests for deploying StellarOps using Kustomize.

## Directory Structure

```
k8s/
├── base/                    # Base manifests (shared across environments)
│   ├── kustomization.yaml   # Kustomize configuration
│   ├── namespace.yaml       # StellarOps namespace
│   ├── ingress.yaml         # Ingress for routing
│   ├── backend/             # Elixir/Phoenix backend
│   │   ├── deployment.yaml
│   │   ├── service.yaml
│   │   ├── configmap.yaml
│   │   ├── secret.yaml
│   │   ├── serviceaccount.yaml
│   │   └── hpa.yaml
│   ├── orbital/             # Rust gRPC service
│   │   ├── deployment.yaml
│   │   ├── service.yaml
│   │   ├── configmap.yaml
│   │   └── hpa.yaml
│   ├── frontend/            # React/nginx frontend
│   │   ├── deployment.yaml
│   │   ├── service.yaml
│   │   └── configmap.yaml
│   ├── postgres/            # PostgreSQL database
│   │   ├── statefulset.yaml
│   │   ├── service.yaml
│   │   └── secret.yaml
│   ├── prometheus/          # Prometheus monitoring
│   │   ├── deployment.yaml
│   │   ├── service.yaml
│   │   ├── configmap.yaml
│   │   ├── rbac.yaml
│   │   └── pvc.yaml
│   └── grafana/             # Grafana dashboards
│       ├── deployment.yaml
│       ├── service.yaml
│       ├── secret.yaml
│       ├── pvc.yaml
│       ├── configmap-datasources.yaml
│       └── configmap-dashboards-config.yaml
└── overlays/
    ├── dev/                 # Development environment overrides
    │   ├── kustomization.yaml
    │   └── namespace.yaml
    └── prod/                # Production environment overrides
        ├── kustomization.yaml
        └── namespace.yaml
```

## Prerequisites

1. **Local Kubernetes Cluster** (choose one):
   - [kind](https://kind.sigs.k8s.io/) - `kind create cluster --name stellarops`
   - [minikube](https://minikube.sigs.k8s.io/) - `minikube start`
   - [k3d](https://k3d.io/) - `k3d cluster create stellarops`

2. **kubectl** - Kubernetes CLI

3. **kustomize** - Already bundled with kubectl (`kubectl kustomize`)

4. **nginx-ingress** controller:
   ```bash
   # For kind
   kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/kind/deploy.yaml

   # For minikube
   minikube addons enable ingress
   ```

## Deployment

### Development Environment

```bash
# Preview what will be applied
kubectl kustomize k8s/overlays/dev

# Apply to cluster
kubectl apply -k k8s/overlays/dev

# Or using kustomize build
kustomize build k8s/overlays/dev | kubectl apply -f -
```

### Production Environment

```bash
# Preview
kubectl kustomize k8s/overlays/prod

# Apply
kubectl apply -k k8s/overlays/prod
```

## Verify Deployment

```bash
# Check pods
kubectl get pods -n stellarops-dev

# Check services
kubectl get svc -n stellarops-dev

# Check ingress
kubectl get ingress -n stellarops-dev

# View logs
kubectl logs -n stellarops-dev -l app=backend -f

# Port forward to access locally
kubectl port-forward -n stellarops-dev svc/frontend 8080:80
kubectl port-forward -n stellarops-dev svc/grafana 3000:3000
```

## Access the Application

1. Add to `/etc/hosts` (or `C:\Windows\System32\drivers\etc\hosts` on Windows):
   ```
   127.0.0.1 stellarops-dev.local
   ```

2. For kind, ensure port forwarding:
   ```bash
   kubectl port-forward -n ingress-nginx svc/ingress-nginx-controller 80:80 443:443
   ```

3. Access:
   - Frontend: http://stellarops-dev.local
   - API: http://stellarops-dev.local/api
   - Grafana: http://stellarops-dev.local/grafana (admin/stellarops)

## Elixir Clustering

The backend is configured with libcluster for distributed Erlang clustering:

- **Strategy**: Kubernetes API-based discovery
- **ServiceAccount**: `backend` with RBAC for endpoint listing
- **Headless Service**: `backend-headless` for DNS-based discovery fallback

Environment variables for clustering:
- `CLUSTER_ENABLED=true` - Enable clustering
- `CLUSTER_STRATEGY=kubernetes` - Use Kubernetes API
- `CLUSTER_KUBERNETES_SELECTOR=app=backend` - Pod selector
- `CLUSTER_KUBERNETES_NAMESPACE=stellarops` - Namespace

## Database Migrations

Run Ecto migrations as a Kubernetes Job:

```bash
kubectl create job --from=cronjob/migration-job migrate-$(date +%s) -n stellarops-dev
```

Or manually:

```bash
kubectl exec -it -n stellarops-dev deploy/backend -- /app/bin/migrate
```

## Scaling

Manual scaling:
```bash
kubectl scale deployment backend --replicas=5 -n stellarops-dev
```

HPA will automatically scale based on CPU/memory (configured in `hpa.yaml`).

## Cleanup

```bash
# Delete dev environment
kubectl delete -k k8s/overlays/dev

# Delete prod environment
kubectl delete -k k8s/overlays/prod
```

## Customization

### Override Images

In your overlay's `kustomization.yaml`:

```yaml
images:
  - name: ghcr.io/stellarops/backend
    newName: your-registry/backend
    newTag: v1.2.3
```

### Add Secrets

For production, use sealed-secrets or external-secrets-operator instead of plain Secret resources:

```bash
# Install sealed-secrets
helm install sealed-secrets sealed-secrets/sealed-secrets -n kube-system

# Seal a secret
kubeseal < secret.yaml > sealed-secret.yaml
```

### Custom ConfigMaps

Use Kustomize's `configMapGenerator` in overlays:

```yaml
configMapGenerator:
  - name: backend-config
    behavior: merge
    literals:
      - MY_CUSTOM_VAR=value
```
