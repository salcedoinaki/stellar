# StellarOps

> Distributed mission orchestration for a simulated satellite constellation, built on Elixir/Erlang (BEAM) with a TypeScript operations console, containerised and ready for cloud deployment.

## Quick Start (Docker)

```bash
docker compose -f docker-compose.dev.yml up -d
docker compose -f docker-compose.dev.yml exec backend iex -S mix
```

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
