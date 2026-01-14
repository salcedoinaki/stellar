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

---

# Code Review – Future Tasks

> This section documents bugs, flaws, improvements, and features identified during the January 2026 code review.

## 🐛 Bugs (High Priority)

### BUG-1: Orbital Client Uses Mock Data Only
- **File:** `apps/stellar_core/lib/stellar_core/orbital.ex`
- **Issue:** The `call_grpc/2` function only returns mock responses and never actually calls the Rust orbital service.
- **Fix:** Implement actual HTTP/gRPC client calls using `Req` or `Finch`.

### BUG-2: MissionScheduler Calls Non-existent Function
- **File:** `apps/stellar_core/lib/stellar_core/scheduler/mission_scheduler.ex`
- **Issue:** `Satellite.update_state/2` is called but doesn't exist. Only `update_energy/2`, `update_memory/2`, `set_mode/2`, and `update_position/2` exist.
- **Fix:** Replace with the correct function or implement `update_state/2`.

### BUG-3: State.update_position/2 Type Guard Issue
- **File:** `apps/stellar_core/lib/stellar_core/satellite/state.ex`
- **Issue:** Guard uses `is_float(x)` but positions can be integers, causing crashes.
- **Fix:** Change guard to use `is_number/1` instead of `is_float/1`.

### BUG-4: Frontend Dashboard Mode Mismatch
- **File:** `frontend/src/pages/Dashboard.tsx`
- **Issue:** Frontend filters for `mode === 'critical'` and uses `standby`, but backend only supports: `nominal`, `safe`, `survival`.
- **Fix:** Align frontend mode constants with backend enum values.

### BUG-5: Blocking Sleep in Channel
- **File:** `apps/stellar_web/lib/stellar_web/channels/satellite_channel.ex`
- **Issue:** `:timer.sleep(5)` blocks the channel process and can cause issues under load.
- **Fix:** Remove or use `Process.send_after/3` for non-blocking delays.

### BUG-6: Random ID Generation Collision Risk
- **Files:** `SatelliteController`, `SatelliteChannel`
- **Issue:** `generate_id/0` uses `:rand.uniform(99999)` which has collision risk.
- **Fix:** Use UUIDs or NanoIDs for satellite identifiers.

---

## ⚠️ Flaws & Code Quality Issues

### FLAW-1: Missing Error Handling in API Client
- **File:** `frontend/src/services/api.ts`
- **Issue:** `deleteSatellite` doesn't handle non-JSON error responses properly.
- **Fix:** Add try/catch around JSON parsing for error responses.

### FLAW-2: No Input Validation in WebSocket Channel
- **File:** `apps/stellar_web/lib/stellar_web/channels/satellite_channel.ex`
- **Issue:** No validation of payload data types (e.g., invalid mode strings accepted).
- **Fix:** Add Ecto changesets or manual validation for incoming payloads.

### FLAW-3: Hardcoded DB Hostname in Test Config
- **File:** `config/test.exs`
- **Issue:** Uses `hostname: "db"` which only works in Docker, failing for local dev.
- **Fix:** Use environment variable with fallback: `System.get_env("DB_HOST", "localhost")`.

### FLAW-4: K8s Secret Not Properly Encoded
- **File:** `k8s/base/backend/secret.yaml`
- **Issue:** Secret key base is a placeholder, not base64 encoded, with a warning to change.
- **Fix:** Use External Secrets, Sealed Secrets, or proper secret management.

### FLAW-5: Missing Rate Limiting
- **File:** `apps/stellar_web/lib/stellar_web/router.ex`
- **Issue:** No rate limiting on API endpoints, vulnerable to abuse.
- **Fix:** Add `PlugAttack` or similar rate limiting middleware.

### FLAW-6: No Authentication/Authorization
- **File:** `apps/stellar_web/lib/stellar_web/channels/user_socket.ex`
- **Issue:** WebSocket accepts all connections without authentication.
- **Fix:** Implement Guardian/JWT authentication for API and WebSocket.

### FLAW-7: Alarms Stored Only in ETS
- **File:** `apps/stellar_core/lib/stellar_core/alarms.ex`
- **Issue:** ETS is in-memory only - alarms lost on restart.
- **Fix:** Persist alarms to PostgreSQL.

### FLAW-8: Missing libcluster Configuration
- **Issue:** K8s deployment references Elixir clustering but no `libcluster` config exists.
- **Fix:** Add `libcluster` dependency and DNS-based cluster configuration.

### FLAW-9: Docker Compose Dev Uses Release Build for Rust
- **File:** `docker-compose.dev.yml`
- **Issue:** Orbital service runs `cargo build --release` which is slow for development.
- **Fix:** Use debug builds for development: `cargo build`.

---

## 🔧 Improvements

### IMP-1: Implement Real gRPC/HTTP Client in Orbital Module
- Replace mock responses with actual HTTP calls using `Req` or `Finch` library.

### IMP-2: Use UUID for Satellite IDs
- Replace random number generation with `Ecto.UUID.generate/0` or NanoID.

### IMP-3: Add Database Migrations for Alarms
- Create `alarms` table and persist alarms to PostgreSQL for durability.

### IMP-4: Add OpenAPI/Swagger Documentation
- Use `open_api_spex` to document REST API with auto-generated specs.

### IMP-5: Add WebSocket Heartbeat Handling
- Implement proper heartbeat/ping handling in `frontend/src/services/socket.ts`.

### IMP-6: Emit Telemetry Events from Business Logic
- Add `Telemetry.execute/3` calls for satellite operations, mission scheduling, etc.

### IMP-7: Add Property-Based Tests with StreamData
- Implement property tests for satellite state invariants as mentioned in Phase 2.

### IMP-8: Database Connection Pooling Configuration
- Make pool size configurable via environment variables for dev and prod.

### IMP-9: Request ID Propagation
- Propagate request IDs through the system for distributed tracing.

### IMP-10: Add React Error Boundaries
- Wrap components with error boundaries for graceful error display.

### IMP-11: Add Retry Logic to Frontend API Calls
- Configure React Query with proper retry logic for failed requests.

### IMP-12: Shared Mode Enum Between Frontend and Backend
- Create a shared constant/type for satellite modes to prevent mismatches.

---

## ✨ Features to Add

### FEAT-1: Complete Orbital Service Integration
- Implement actual HTTP client in `StellarCore.Orbital` to call Rust service.

### FEAT-2: Scheduled Position Updates
- Add GenServer or Quantum job to periodically update satellite positions.

### FEAT-3: TLE Management API
- Endpoints to manage TLE data (fetch from Space-Track, CelesTrak).

### FEAT-4: Ground Station Pass Prediction
- Expose visibility calculations from orbital service to frontend.

### FEAT-5: Real-time Map Position Updates
- Push position updates via WebSocket to `SatelliteMap.tsx` instead of random positions.

### FEAT-6: Mission/Task UI
- Frontend pages for creating, viewing, and managing missions.

### FEAT-7: Alarm Dashboard UI
- Frontend page to view, acknowledge, and resolve alarms.

### FEAT-8: User Authentication System
- Implement Guardian/JWT auth with login, registration, and session management.

### FEAT-9: Multi-tenancy Support
- Support for multiple organizations with isolated satellite constellations.

### FEAT-10: Satellite Command Queue
- Implement command queue with audit logging for satellite operations.

### FEAT-11: Telemetry Time-Series Storage
- Store historical telemetry in TimescaleDB or InfluxDB for analytics.

### FEAT-12: Email/Slack Notifications
- Send notifications for critical alarms via external integrations.

### FEAT-13: Implement CI/CD Pipeline
- Complete GitHub Actions workflows for lint, test, build, and deploy.

### FEAT-14: Database Backup CronJob
- K8s CronJob for automated PostgreSQL backups.

### FEAT-15: Chaos/Resilience Testing
- Tests for supervisor resilience (kill satellites, verify auto-restart).

### FEAT-16: GraphQL API (Optional)
- Alternative to REST for more flexible frontend querying.

### FEAT-17: Offline/Degraded Mode Handling
- Frontend gracefully handles backend or orbital service unavailability.

---

## 📊 Task Summary

| Category     | Count | Priority |
|--------------|-------|----------|
| Bugs         | 6     | 🔴 High  |
| Flaws        | 9     | 🟠 Medium |
| Improvements | 12    | 🟡 Normal |
| Features     | 17    | 🔵 Backlog |
| **Total**    | **44** |          |

### Recommended Priority Order
1. **BUG-2** – Fix missing `Satellite.update_state/2` (breaks mission scheduler)
2. **BUG-3** – Fix type guard for positions (causes crashes)
3. **BUG-1** – Implement orbital service integration
4. **BUG-4** – Align frontend/backend mode constants
5. **FLAW-6** – Add authentication (security critical)
6. **FLAW-5** – Add rate limiting (security)
7. **FEAT-13** – Implement CI/CD pipeline
