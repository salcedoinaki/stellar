import { MapContainer, TileLayer, Marker, Popup, Polyline } from 'react-leaflet'
import L from 'leaflet'
import type { Satellite } from '../types'

interface SatelliteMapProps {
  satellites: Satellite[]
  selectedId?: string | null
  onSelectSatellite?: (id: string) => void
  height?: string
}

// Custom satellite icon
const createSatelliteIcon = (mode: string) => {
  const color = mode === 'nominal' ? '#22c55e' : mode === 'safe' ? '#f59e0b' : '#ef4444'
  
  return L.divIcon({
    className: 'satellite-marker',
    html: `
      <div style="
        width: 24px;
        height: 24px;
        background: ${color};
        border: 2px solid white;
        border-radius: 50%;
        box-shadow: 0 0 10px ${color};
        display: flex;
        align-items: center;
        justify-content: center;
        font-size: 12px;
      ">🛰️</div>
    `,
    iconSize: [24, 24],
    iconAnchor: [12, 12],
    popupAnchor: [0, -12],
  })
}

// Ground station icon
const groundStationIcon = L.divIcon({
  className: 'ground-station-marker',
  html: `
    <div style="
      width: 20px;
      height: 20px;
      background: #3b82f6;
      border: 2px solid white;
      border-radius: 4px;
      display: flex;
      align-items: center;
      justify-content: center;
      font-size: 10px;
    ">📡</div>
  `,
  iconSize: [20, 20],
  iconAnchor: [10, 10],
  popupAnchor: [0, -10],
})

export default function SatelliteMap({
  satellites,
  selectedId,
  onSelectSatellite,
  height = '500px',
}: SatelliteMapProps) {
  // Filter satellites with valid positions
  const mappableSatellites = satellites.filter(
    (sat) => sat.latitude !== undefined && sat.longitude !== undefined
  )

  // Example ground stations
  const groundStations = [
    { id: 'gs-1', name: 'Svalbard', lat: 78.2, lon: 15.6 },
    { id: 'gs-2', name: 'McMurdo', lat: -77.8, lon: 166.7 },
    { id: 'gs-3', name: 'Wallops', lat: 37.9, lon: -75.5 },
  ]

  // Generate orbit path for selected satellite (simulated)
  const orbitPath = selectedId
    ? Array.from({ length: 36 }, (_, i) => {
        const angle = (i / 36) * 2 * Math.PI
        const selectedSat = satellites.find((s) => s.id === selectedId)
        if (!selectedSat?.latitude || !selectedSat?.longitude) return null
        
        // Simple circular approximation
        const lat = selectedSat.latitude + Math.sin(angle) * 40
        const lon = ((selectedSat.longitude + i * 10) % 360) - 180
        return [lat, lon] as [number, number]
      }).filter(Boolean) as [number, number][]
    : []

  return (
    <div className="rounded-xl overflow-hidden border border-slate-700" style={{ height }}>
      <MapContainer
        center={[0, 0]}
        zoom={2}
        style={{ height: '100%', width: '100%' }}
        className="z-0"
      >
        <TileLayer
          attribution='&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a>'
          url="https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png"
        />

        {/* Orbit path */}
        {orbitPath.length > 0 && (
          <Polyline
            positions={orbitPath}
            pathOptions={{
              color: '#38bdf8',
              weight: 2,
              opacity: 0.6,
              dashArray: '5, 10',
            }}
          />
        )}

        {/* Satellites */}
        {mappableSatellites.map((satellite) => (
          <Marker
            key={satellite.id}
            position={[satellite.latitude!, satellite.longitude!]}
            icon={createSatelliteIcon(satellite.mode)}
            eventHandlers={{
              click: () => onSelectSatellite?.(satellite.id),
            }}
          >
            <Popup>
              <div className="text-slate-900">
                <strong>{satellite.id}</strong>
                <br />
                Mode: {satellite.mode}
                <br />
                Energy: {Math.round(satellite.energy)}%
                <br />
                Alt: {satellite.altitude?.toFixed(1) || 'N/A'} km
              </div>
            </Popup>
          </Marker>
        ))}

        {/* Ground stations */}
        {groundStations.map((gs) => (
          <Marker
            key={gs.id}
            position={[gs.lat, gs.lon]}
            icon={groundStationIcon}
          >
            <Popup>
              <div className="text-slate-900">
                <strong>📡 {gs.name}</strong>
                <br />
                Ground Station
              </div>
            </Popup>
          </Marker>
        ))}
      </MapContainer>
    </div>
  )
}
