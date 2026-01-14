import { useEffect } from 'react'
import { useQuery } from '@tanstack/react-query'
import { api } from '../services/api'
import { useSatelliteStore } from '../store/satelliteStore'
import { SatelliteMap, SatelliteCard } from '../components'

export default function MapView() {
  const { satellites, setSatellites, selectedSatelliteId, selectSatellite } = useSatelliteStore()

  // Fetch satellites
  const { data: satelliteList, isLoading } = useQuery({
    queryKey: ['satellites'],
    queryFn: api.satellites.list,
    refetchInterval: 10000,
  })

  // Update store when data changes
  useEffect(() => {
    if (satelliteList) {
      setSatellites(satelliteList)
    }
  }, [satelliteList, setSatellites])

  // Add mock positions for demo (in real app, this would come from orbital service)
  const satellitesWithPositions = Array.from(satellites.values()).map((sat) => ({
    ...sat,
    latitude: sat.latitude ?? (Math.random() * 100 - 50),
    longitude: sat.longitude ?? (Math.random() * 360 - 180),
    altitude: sat.altitude ?? (350 + Math.random() * 100),
  }))

  const selectedSatellite = selectedSatelliteId
    ? satellitesWithPositions.find((s) => s.id === selectedSatelliteId)
    : null

  if (isLoading) {
    return (
      <div className="flex items-center justify-center h-96">
        <div className="text-stellar-400 text-lg">Loading map data...</div>
      </div>
    )
  }

  return (
    <div className="space-y-6">
      {/* Header */}
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-3xl font-bold text-white">Constellation Map</h1>
          <p className="text-slate-400 mt-1">
            Real-time satellite positions and ground stations
          </p>
        </div>
        {selectedSatelliteId && (
          <button
            onClick={() => selectSatellite(null)}
            className="px-4 py-2 bg-slate-700 hover:bg-slate-600 text-white rounded-lg transition-colors"
          >
            Clear Selection
          </button>
        )}
      </div>

      {/* Map and Sidebar */}
      <div className="grid grid-cols-1 lg:grid-cols-4 gap-6">
        {/* Map */}
        <div className="lg:col-span-3">
          <SatelliteMap
            satellites={satellitesWithPositions}
            selectedId={selectedSatelliteId}
            onSelectSatellite={selectSatellite}
            height="600px"
          />
        </div>

        {/* Sidebar */}
        <div className="space-y-4">
          {/* Selected Satellite Info */}
          {selectedSatellite && (
            <div className="bg-slate-800 rounded-xl p-4 border border-stellar-500">
              <h3 className="text-sm text-slate-400 mb-2">Selected Satellite</h3>
              <SatelliteCard satellite={selectedSatellite} />
            </div>
          )}

          {/* Legend */}
          <div className="bg-slate-800 rounded-xl p-4 border border-slate-700">
            <h3 className="text-sm font-semibold text-white mb-3">Legend</h3>
            <div className="space-y-2 text-sm">
              <div className="flex items-center gap-2">
                <div className="w-3 h-3 rounded-full bg-green-500" />
                <span className="text-slate-300">Nominal</span>
              </div>
              <div className="flex items-center gap-2">
                <div className="w-3 h-3 rounded-full bg-yellow-500" />
                <span className="text-slate-300">Safe Mode</span>
              </div>
              <div className="flex items-center gap-2">
                <div className="w-3 h-3 rounded-full bg-red-500" />
                <span className="text-slate-300">Critical</span>
              </div>
              <div className="flex items-center gap-2">
                <div className="w-3 h-3 rounded bg-blue-500" />
                <span className="text-slate-300">Ground Station</span>
              </div>
            </div>
          </div>

          {/* Quick Stats */}
          <div className="bg-slate-800 rounded-xl p-4 border border-slate-700">
            <h3 className="text-sm font-semibold text-white mb-3">Quick Stats</h3>
            <div className="space-y-2 text-sm">
              <div className="flex items-center justify-between">
                <span className="text-slate-400">Total Satellites</span>
                <span className="text-white font-mono">{satellitesWithPositions.length}</span>
              </div>
              <div className="flex items-center justify-between">
                <span className="text-slate-400">Ground Stations</span>
                <span className="text-white font-mono">3</span>
              </div>
              <div className="flex items-center justify-between">
                <span className="text-slate-400">Active Passes</span>
                <span className="text-white font-mono">2</span>
              </div>
            </div>
          </div>

          {/* Satellite List */}
          <div className="bg-slate-800 rounded-xl p-4 border border-slate-700">
            <h3 className="text-sm font-semibold text-white mb-3">Satellites</h3>
            <div className="space-y-2 max-h-64 overflow-y-auto">
              {satellitesWithPositions.length === 0 ? (
                <div className="text-slate-400 text-sm">No satellites</div>
              ) : (
                satellitesWithPositions.map((sat) => (
                  <SatelliteCard key={sat.id} satellite={sat} compact />
                ))
              )}
            </div>
          </div>
        </div>
      </div>
    </div>
  )
}
