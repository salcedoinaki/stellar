# StellarOps

> Distributed mission orchestration for a simulated satellite constellation, built on Elixir/Erlang (BEAM) with a TypeScript operations console, containerised and ready for cloud deployment.

## Quick Start (Docker)

```bash
# Start all services
docker compose -f docker-compose.dev.yml up -d --build

# Initialize the database (first time only)
docker compose -f docker-compose.dev.yml exec backend mix ecto.setup

# Access the Elixir shell
docker compose -f docker-compose.dev.yml exec backend iex -S mix
```

**Endpoints:**
- Frontend: http://localhost:5173
- Backend API: http://localhost:4000
- Orbital Service: http://localhost:9090

## Project Structure

```
stellarops/
├── apps/
│   ├── stellar_core/      # OTP core: supervisors, GenServers
│   ├── stellar_web/       # Phoenix API + WebSocket
│   └── stellar_data/      # Ecto schemas + Postgres
├── services/
│   └── orbital_service/   # Rust gRPC orbital propagation
├── frontend/              # React + Vite + TypeScript
├── infrastructure/
│   ├── docker/
│   ├── kubernetes/
│   └── monitoring/
└── config/                # Elixir umbrella config
```

## Development

See [PLAN.md](../PLAN.md) for the full roadmap.

## License

MIT
