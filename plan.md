# StellarOps Roadmap (Umbrella Elixir, React, Docker-first)

> Fault-tolerant mission runtime for satellite constellations. Core on BEAM (Elixir umbrella + Phoenix), Rust orbital microservice, React/TS frontend. Docker from Phase 1.

## Conventions
- Workspace: `stellarops/` (root). Use Elixir umbrella (`mix new stellarops --umbrella`).
- Apps: `apps/stellar_core`, `apps/stellar_web`, `apps/stellar_data` (Ecto), `services/orbital_service` (Rust), `frontend/` (React+Vite).
- Branching: `main` stable, feature branches per phase.
- Docker from Day 1: dev via `docker-compose.dev.yml`; prod images later.

## Prerequisites
- Elixir/OTP, Erlang, Node 20+, Rust stable, Docker Desktop, `protoc`, Git.
- VS Code + ElixirLS + Rust Analyzer + ESLint/Prettier.

## Phase 0 – Bootstrap & Tooling (Day 0)
- Create repo `stellarops`.
- Add `.gitignore` (Elixir, Node, Rust, Docker, VSCode).
- Add `LICENSE` (MIT/Apache2), `README` placeholder.
- Create umbrella skeleton: `mix new stellarops --umbrella`.
- Add base Docker assets:
  - `docker-compose.dev.yml` with minimal Elixir container running `mix phx.server` later, Postgres, pgadmin (optional).
  - Base Dockerfiles stubs: `infrastructure/docker/Dockerfile.elixir.dev`, `Dockerfile.frontend.dev`, `Dockerfile.rust.dev`.
- CI skeleton: `.github/workflows/ci.yml` stub (runs `echo TODO`).

## Phase 1 – "Hello, Satellite" (Single GenServer, Dockerized)
**Goal:** Minimal supervised GenServer representing one satellite; runs via Docker Compose.
- Create `apps/stellar_core` (OTP app): `SatelliteServer` GenServer with state (id, mode, energy, memory).
- Add `Application` supervisor with `SatelliteServer` child.
- Tests: GenServer init/handle_call, state updates.
- Docker dev:
  - Elixir dev image installs hex/rebar, deps cached.
  - `docker-compose.dev.yml` runs `mix test` and `iex -S mix` target.
- Deliverable: `docker compose -f docker-compose.dev.yml run --rm backend mix test` green; `iex` can ping satellite.

## Phase 2 – Multi-Satellite Supervisor & Registry
**Goal:** DynamicSupervisor + Registry to manage multiple satellites; resilience demo.
- Add `Satellite.Supervisor` (DynamicSupervisor) and `Satellite.Registry` (Registry via `:unique`).
- API: start/stop satellite, get state, update mode/energy/memory.
- Property tests (StreamData) for basic invariants.
- Observability seeds: log metadata per sat id.
- Docker: same compose; mount code for live reload (`mix phx.server` soon).
- Deliverable: script spawning 10 satellites, killing one, auto-restart verified in tests.

## Phase 3 – Phoenix Gateway (Umbrella Web Layer)
**Goal:** Expose REST + WebSocket for satellites.
- Add `apps/stellar_web` with Phoenix (no HTML): `mix phx.new stellar_web --no-ecto --no-html --no-live --app stellar_web --umbrella`.
- Endpoints: `GET /api/satellites`, `GET /api/satellites/:id`, `POST /api/satellites` (create/spawn).
- Channel `satellites:lobby` broadcasting sat state changes (via PubSub).
- Integration tests for controllers and channel.
- Compose: add port 4000, env vars for `PHX_SERVER=true`.
- Deliverable: curl returns JSON, ws client receives broadcasts.

## Phase 4 – Persistence (Ecto/Postgres)
**Goal:** Persist satellites and telemetry.
- Add `apps/stellar_data` with `Ecto.Repo` and Postgres deps.
- Schemas: `Satellite`, `TelemetryEvent`, `Command` (basic fields). Migrations.
- Context functions in `stellar_core` delegating to Repo.
- Seed data for dev.
- Compose: Postgres service with volume, healthcheck; backend waits-on db.
- Tests: Ecto sandbox, schema tests, context tests.
- Deliverable: data survives restarts; tests green.

## Phase 5 – Rust Orbital Service (gRPC)
**Goal:** Externalize orbital propagation.
- Create `services/orbital_service` (Rust + Tonic).
- `proto/orbital.proto`: `PropagatePosition(Tle, timestamp) -> Position`; `Visibility(sat_id, ground_id, window) -> Pass[]` (stubbed initially).
- Implement mock logic first; later integrate `sgp4` crate.
- Expose Prometheus metrics (`/metrics` via `prometheus` crate or `opentelemetry-prometheus`).
- Elixir gRPC client (e.g., `grpc` or `tonic`-generated stubs via `prost`? If simpler, start with HTTP JSON).
- Docker: multi-stage Rust build, small runtime image.
- Deliverable: Elixir calls Rust service via gRPC/HTTP and returns position.

## Phase 6 – React Frontend (Vite, TS, WS)
**Goal:** Real-time dashboard consuming API/WS.
- Create `frontend` with Vite React TS template.
- Add Phoenix Channels client (`phoenix` npm) or native ws.
- Views: Constellation list, simple Leaflet 2D map, live telemetry cards.
- State/query: React Query; light state store (Zustand/Jotai).
- Charts: Recharts for telemetry.
- Docker: frontend dev server in compose, served on 5173; env var for API base.
- Deliverable: Frontend shows live satellites and updates via WS.

## Phase 7 – Containerization Hardening
**Goal:** Production-grade images and compose.
- Multi-stage Dockerfiles:
  - Elixir release image (builder with deps/assets, runner minimal, e.g., Debian slim or Distroless; consider avoiding Alpine for BEAM DNS issues).
  - Rust release image (builder + slim runtime).
  - Frontend static build served by nginx or `caddy`.
- `docker-compose.yml` (prod-like) with healthchecks, proper env vars, named volumes.
- `.dockerignore` for all components.
- Deliverable: `docker compose up` runs full stack locally (backend, orbital, frontend, postgres).

## Phase 8 – Observability
**Goal:** Metrics, logs, dashboards.
- Elixir Telemetry -> Prometheus exporter (e.g., `prom_ex` or `telemetry_metrics_prometheus_core`).
- Domain metrics: `stellar_satellites_active`, `stellar_tasks_pending`, `stellar_tasks_failed_total`, `stellar_energy_avg`.
- Rust: expose gRPC call latency metrics.
- Compose: add Prometheus + Grafana with starter dashboards.
- Structured JSON logging (Elixir LoggerJSON, Rust tracing_subscriber JSON).
- Deliverable: Grafana shows live metrics; logs structured.

## Phase 9 – Kubernetes (k8s + Kustomize)
**Goal:** Deploy to local k8s (kind/minikube/k3d).
- Manifests per service: Deployments, Services, ConfigMaps/Secrets, Ingress.
- Kustomize overlays: `dev`, `prod`.
- HPA for backend (CPU/memory), Rust service.
- Elixir clustering via `libcluster` DNS in k8s.
- Postgres as statefulset (or use managed DB in prod).
- Deliverable: `kustomize build overlays/dev | kubectl apply -f -` brings up stack; frontend reachable via Ingress.

## Phase 10 – CI/CD
**Goal:** Automated test/build/publish/deploy.
- GitHub Actions workflow:
  - Lint/test matrix: backend (mix format/test), frontend (npm lint/test), rust (cargo fmt/test).
  - Build & push images with tags `:sha` and `:latest` to GHCR.
  - Deploy job (on main) applying kustomize manifests; run `mix ecto.migrate` as k8s Job.
- Optional: Preview envs per PR via ephemeral namespaces.
- Deliverable: Push to main triggers build+deploy to dev namespace.

## Phase 11 – Scheduling & Mission Logic (Stretch)
**Goal:** Improve domain realism.
- Mission Scheduler: priority + deadline + resource constraints.
- Ground stations simulation, downlink windows, bandwidth constraints.
- Task lifecycle states (pending, running, done, failed, canceled).
- Retry/backoff and alarms.

