import { useState, useEffect } from 'react'
import OrbitalViewer from '../components/OrbitalViewer'
import { api } from '../services/api'
import type { Satellite, Conjunction, GroundStation } from '../types'

export default function OrbitalView() {
  const [satellites, setSatellites] = useState<Satellite[]>([])
  const [conjunctions, setConjunctions] = useState<Conjunction[]>([])
  const [groundStations, setGroundStations] = useState<GroundStation[]>([])
  const [selectedConjunctionId, setSelectedConjunctionId] = useState<string | null>(null)
  const [loading, setLoading] = useState(true)

  useEffect(() => {
    async function fetchData() {
      try {
        setLoading(true)
        const [sats, conjs] = await Promise.all([
          api.satellites.list(),
          api.conjunctions.list({ status: 'detected' }),
        ])
        setSatellites(sats || [])
        setConjunctions(conjs || [])
        
        // Mock ground stations for now
        setGroundStations([
          { id: '1', name: 'Goldstone', latitude: 35.4267, longitude: -116.89, elevation_mask: 5 },
          { id: '2', name: 'Canberra', latitude: -35.4011, longitude: 148.9819, elevation_mask: 5 },
          { id: '3', name: 'Madrid', latitude: 40.4315, longitude: -4.2478, elevation_mask: 5 },
          { id: '4', name: 'Svalbard', latitude: 78.2292, longitude: 15.4097, elevation_mask: 3 },
        ])
      } catch (error) {
        console.error('Failed to fetch orbital data:', error)
      } finally {
        setLoading(false)
      }
    }
    fetchData()
  }, [])

  return (
    <div className="h-[calc(100vh-200px)] flex gap-4">
      {/* Orbital Viewer */}
      <div className="flex-1 bg-slate-800 rounded-lg border border-slate-700">
        {loading ? (
          <div className="w-full h-full flex items-center justify-center text-slate-400">
            Loading orbital data...
          </div>
        ) : (
          <OrbitalViewer
            satellites={satellites}
            conjunctions={conjunctions}
            groundStations={groundStations}
            selectedConjunctionId={selectedConjunctionId || undefined}
            onSelectConjunction={(id) => setSelectedConjunctionId(id)}
          />
        )}
      </div>

      {/* Sidebar */}
      <div className="w-80 bg-slate-800 rounded-lg border border-slate-700 flex flex-col">
        <div className="p-4 border-b border-slate-700">
          <h2 className="text-lg font-semibold text-white">Active Conjunctions</h2>
          <p className="text-xs text-slate-400 mt-1">
            Click to highlight in orbital view
          </p>
        </div>

        <div className="flex-1 overflow-y-auto">
          {conjunctions.length === 0 ? (
            <div className="p-4 text-center text-slate-400">
              No active conjunctions
            </div>
          ) : (
            <div className="divide-y divide-slate-700">
              {conjunctions.map((conj) => {
                const isSelected = conj.id === selectedConjunctionId
                const severityColors = {
                  critical: 'border-red-500 bg-red-500/10',
                  high: 'border-orange-500 bg-orange-500/10',
                  medium: 'border-yellow-500 bg-yellow-500/10',
                  low: 'border-green-500 bg-green-500/10',
                }

                return (
                  <div
                    key={conj.id}
                    onClick={() => setSelectedConjunctionId(isSelected ? null : conj.id)}
                    className={`p-3 cursor-pointer transition-colors ${
                      isSelected
                        ? 'bg-stellar-600/20 border-l-2 border-stellar-500'
                        : 'hover:bg-slate-700/50'
                    }`}
                  >
                    <div className="flex items-center gap-2 mb-1">
                      <span
                        className={`text-xs px-1.5 py-0.5 rounded uppercase font-medium border ${
                          severityColors[conj.severity]
                        }`}
                      >
                        {conj.severity}
                      </span>
                      <span className="text-xs text-slate-400">
                        {conj.object_id.slice(0, 8)}
                      </span>
                    </div>
                    <div className="text-sm text-white">
                      Asset: {conj.asset_id.slice(0, 8)}...
                    </div>
                    <div className="text-xs text-slate-400 mt-1">
                      Miss: {conj.miss_distance_km.toFixed(2)} km
                    </div>
                    <div className="text-xs text-slate-400">
                      TCA: {new Date(conj.tca).toLocaleString()}
                    </div>
                  </div>
                )
              })}
            </div>
          )}
        </div>

        {/* Selected conjunction details */}
        {selectedConjunctionId && (
          <div className="border-t border-slate-700 p-4">
            {(() => {
              const conj = conjunctions.find((c) => c.id === selectedConjunctionId)
              if (!conj) return null

              return (
                <div className="space-y-2 text-sm">
                  <h3 className="font-semibold text-white">Conjunction Details</h3>
                  <div className="grid grid-cols-2 gap-2 text-xs">
                    <div>
                      <span className="text-slate-400">Miss Distance:</span>
                      <div className="text-white font-mono">
                        {conj.miss_distance_km.toFixed(2)} km
                      </div>
                    </div>
                    <div>
                      <span className="text-slate-400">Rel. Velocity:</span>
                      <div className="text-white font-mono">
                        {conj.relative_velocity_km_s.toFixed(2)} km/s
                      </div>
                    </div>
                    <div>
                      <span className="text-slate-400">Probability:</span>
                      <div className="text-white font-mono">
                        {(conj.probability * 100).toFixed(4)}%
                      </div>
                    </div>
                    <div>
                      <span className="text-slate-400">Status:</span>
                      <div className="text-white">{conj.status}</div>
                    </div>
                  </div>
                  <button
                    onClick={() => {
                      // Navigate to threat dashboard with this conjunction selected
                      window.location.href = `/threats?id=${conj.id}`
                    }}
                    className="w-full mt-2 px-3 py-1.5 bg-stellar-600 hover:bg-stellar-500 text-white text-xs rounded transition-colors"
                  >
                    View in Threat Dashboard
                  </button>
                </div>
              )
            })()}
          </div>
        )}
      </div>
    </div>
  )
}
