# StellarOps Frontend

Real-time satellite constellation monitoring dashboard built with React, TypeScript, and Vite.

## Features

- 📊 **Dashboard** - Constellation overview with live statistics
- 🛰️ **Satellite List** - Browse and manage satellites with filtering
- 📍 **Detail View** - Individual satellite telemetry and controls
- 🗺️ **Map View** - 2D world map with satellite positions
- ⚡ **Real-time Updates** - Phoenix WebSocket integration
- 📈 **Telemetry Charts** - Recharts-based data visualization

## Tech Stack

- **React 18** - UI framework
- **TypeScript** - Type safety
- **Vite** - Build tool and dev server
- **TailwindCSS** - Styling
- **React Query** - Data fetching and caching
- **Zustand** - State management
- **React Router** - Client-side routing
- **Recharts** - Data visualization
- **React Leaflet** - Interactive maps
- **Phoenix Channels** - WebSocket client

## Development

### Local Development

```bash
# Install dependencies
npm install

# Start dev server
npm run dev

# Run tests
npm test

# Build for production
npm run build
```

### Docker Development

```bash
# From project root
docker compose -f docker-compose.dev.yml up frontend
```

The frontend will be available at http://localhost:5173

## Project Structure

```
src/
├── components/       # Reusable UI components
│   ├── Layout.tsx
│   ├── SatelliteCard.tsx
│   ├── SatelliteMap.tsx
│   └── TelemetryChart.tsx
├── pages/           # Route components
│   ├── Dashboard.tsx
│   ├── SatelliteList.tsx
│   ├── SatelliteDetail.tsx
│   └── MapView.tsx
├── services/        # API and WebSocket clients
│   ├── api.ts
│   └── socket.ts
├── store/           # Zustand state stores
│   └── satelliteStore.ts
├── types/           # TypeScript definitions
│   └── index.ts
├── App.tsx          # Root component
├── main.tsx         # Entry point
└── index.css        # Global styles
```

## Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `VITE_API_URL` | Phoenix backend URL | `http://localhost:4000` |
| `VITE_WS_URL` | WebSocket URL | `ws://localhost:4000` |
| `VITE_ORBITAL_URL` | Orbital service URL | `http://localhost:9090` |

## API Integration

The frontend connects to:

1. **Phoenix REST API** - Satellite CRUD operations
2. **Phoenix Channels** - Real-time satellite updates
3. **Orbital Service** - Position propagation (via HTTP)

## Contributing

1. Follow the existing code style
2. Use TypeScript strictly
3. Write tests for new features
4. Use meaningful commit messages
