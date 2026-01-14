import { Link } from 'react-router-dom'
import type { Satellite, SatelliteMode } from '../types'

interface SatelliteCardProps {
  satellite: Satellite
  compact?: boolean
}

const modeColors: Record<SatelliteMode, string> = {
  nominal: 'bg-green-500',
  safe: 'bg-yellow-500',
  critical: 'bg-red-500',
  standby: 'bg-blue-500',
}

const modeLabels: Record<SatelliteMode, string> = {
  nominal: 'Nominal',
  safe: 'Safe Mode',
  critical: 'Critical',
  standby: 'Standby',
}

export default function SatelliteCard({ satellite, compact = false }: SatelliteCardProps) {
  const { id, mode, energy, memory } = satellite
  const modeColor = modeColors[mode] || 'bg-gray-500'
  const modeLabel = modeLabels[mode] || mode

  if (compact) {
    return (
      <Link
        to={`/satellites/${id}`}
        className="satellite-card bg-slate-800 rounded-lg p-3 border border-slate-700 hover:border-stellar-500 block"
      >
        <div className="flex items-center justify-between">
          <div className="flex items-center gap-2">
            <div className={`w-2 h-2 rounded-full ${modeColor}`} />
            <span className="font-mono text-sm text-white">{id}</span>
          </div>
          <span className="text-xs text-slate-400">{Math.round(energy)}%</span>
        </div>
      </Link>
    )
  }

  return (
    <Link
      to={`/satellites/${id}`}
      className="satellite-card bg-slate-800 rounded-xl p-5 border border-slate-700 hover:border-stellar-500 block"
    >
      {/* Header */}
      <div className="flex items-start justify-between mb-4">
        <div>
          <h3 className="font-mono text-lg font-semibold text-white">{id}</h3>
          <div className="flex items-center gap-2 mt-1">
            <div className={`w-2 h-2 rounded-full ${modeColor}`} />
            <span className="text-sm text-slate-400">{modeLabel}</span>
          </div>
        </div>
        <div className="text-right">
          <span className="text-2xl">🛰️</span>
        </div>
      </div>

      {/* Stats */}
      <div className="space-y-3">
        {/* Energy */}
        <div>
          <div className="flex items-center justify-between text-sm mb-1">
            <span className="text-slate-400">Energy</span>
            <span className="text-white font-mono">{Math.round(energy)}%</span>
          </div>
          <div className="w-full bg-slate-700 rounded-full h-2">
            <div
              className={`h-2 rounded-full transition-all duration-500 ${
                energy > 50 ? 'bg-green-500' : energy > 20 ? 'bg-yellow-500' : 'bg-red-500'
              }`}
              style={{ width: `${Math.min(100, Math.max(0, energy))}%` }}
            />
          </div>
        </div>

        {/* Memory */}
        <div>
          <div className="flex items-center justify-between text-sm mb-1">
            <span className="text-slate-400">Memory</span>
            <span className="text-white font-mono">{Math.round(memory)}%</span>
          </div>
          <div className="w-full bg-slate-700 rounded-full h-2">
            <div
              className={`h-2 rounded-full transition-all duration-500 ${
                memory < 50 ? 'bg-green-500' : memory < 80 ? 'bg-yellow-500' : 'bg-red-500'
              }`}
              style={{ width: `${Math.min(100, Math.max(0, memory))}%` }}
            />
          </div>
        </div>
      </div>

      {/* Position (if available) */}
      {satellite.latitude !== undefined && satellite.longitude !== undefined && (
        <div className="mt-4 pt-4 border-t border-slate-700">
          <div className="grid grid-cols-2 gap-2 text-sm">
            <div>
              <span className="text-slate-400">Lat: </span>
              <span className="text-white font-mono">{satellite.latitude.toFixed(2)}°</span>
            </div>
            <div>
              <span className="text-slate-400">Lon: </span>
              <span className="text-white font-mono">{satellite.longitude.toFixed(2)}°</span>
            </div>
          </div>
        </div>
      )}
    </Link>
  )
}
