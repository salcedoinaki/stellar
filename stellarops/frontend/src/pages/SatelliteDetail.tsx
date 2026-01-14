import { useParams, Link, useNavigate } from 'react-router-dom'
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import { api } from '../services/api'
import { useSatelliteStore } from '../store/satelliteStore'
import { TelemetryChart, StatCard } from '../components'
import type { SatelliteMode } from '../types'

export default function SatelliteDetail() {
  const { id } = useParams<{ id: string }>()
  const navigate = useNavigate()
  const queryClient = useQueryClient()
  const { getTelemetryHistory } = useSatelliteStore()

  // Fetch satellite data
  const { data: satellite, isLoading, error } = useQuery({
    queryKey: ['satellite', id],
    queryFn: () => api.satellites.get(id!),
    enabled: !!id,
  })

  // Fetch satellite state from GenServer
  const { data: state } = useQuery({
    queryKey: ['satellite-state', id],
    queryFn: () => api.satellites.getState(id!),
    enabled: !!id,
    refetchInterval: 5000,
  })

  // Delete mutation
  const deleteMutation = useMutation({
    mutationFn: () => api.satellites.delete(id!),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['satellites'] })
      navigate('/satellites')
    },
  })

  // Mode update mutation
  const modeMutation = useMutation({
    mutationFn: (mode: string) => api.satellites.updateMode(id!, mode),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['satellite', id] })
      queryClient.invalidateQueries({ queryKey: ['satellite-state', id] })
    },
  })

  const telemetryData = getTelemetryHistory(id || '')
  const displayData = state || satellite

  if (isLoading) {
    return (
      <div className="flex items-center justify-center h-96">
        <div className="text-stellar-400 text-lg">Loading satellite data...</div>
      </div>
    )
  }

  if (error || !displayData) {
    return (
      <div className="flex flex-col items-center justify-center h-96">
        <div className="text-red-400 text-lg mb-4">
          {error ? (error as Error).message : 'Satellite not found'}
        </div>
        <Link
          to="/satellites"
          className="px-4 py-2 bg-stellar-600 hover:bg-stellar-500 text-white rounded-lg transition-colors"
        >
          Back to Satellites
        </Link>
      </div>
    )
  }

  const modeColors: Record<SatelliteMode, string> = {
    nominal: 'bg-green-500',
    safe: 'bg-yellow-500',
    critical: 'bg-red-500',
    standby: 'bg-blue-500',
  }

  return (
    <div className="space-y-6">
      {/* Breadcrumb */}
      <nav className="flex items-center gap-2 text-sm text-slate-400">
        <Link to="/" className="hover:text-white">Dashboard</Link>
        <span>/</span>
        <Link to="/satellites" className="hover:text-white">Satellites</Link>
        <span>/</span>
        <span className="text-white">{id}</span>
      </nav>

      {/* Header */}
      <div className="flex items-start justify-between">
        <div className="flex items-center gap-4">
          <div className="text-5xl">🛰️</div>
          <div>
            <h1 className="text-3xl font-bold text-white font-mono">{displayData.id}</h1>
            <div className="flex items-center gap-2 mt-2">
              <div className={`w-3 h-3 rounded-full ${modeColors[displayData.mode]}`} />
              <span className="text-slate-300 capitalize">{displayData.mode} Mode</span>
            </div>
          </div>
        </div>
        <div className="flex items-center gap-3">
          <button
            onClick={() => deleteMutation.mutate()}
            className="px-4 py-2 bg-red-600 hover:bg-red-500 text-white rounded-lg transition-colors"
            disabled={deleteMutation.isPending}
          >
            {deleteMutation.isPending ? 'Deleting...' : 'Delete'}
          </button>
        </div>
      </div>

      {/* Stats Grid */}
      <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
        <StatCard
          label="Energy Level"
          value={Math.round(displayData.energy)}
          unit="%"
          color={displayData.energy > 50 ? 'green' : displayData.energy > 20 ? 'yellow' : 'red'}
        />
        <StatCard
          label="Memory Usage"
          value={Math.round(displayData.memory)}
          unit="%"
          color={displayData.memory < 50 ? 'green' : displayData.memory < 80 ? 'yellow' : 'red'}
        />
        <StatCard
          label="Current Mode"
          value={displayData.mode}
          color={displayData.mode === 'nominal' ? 'green' : displayData.mode === 'safe' ? 'yellow' : 'red'}
        />
        <StatCard
          label="Status"
          value={displayData.mode === 'critical' ? 'Alert' : 'Healthy'}
          color={displayData.mode === 'critical' ? 'red' : 'green'}
        />
      </div>

      {/* Mode Controls */}
      <div className="bg-slate-800 rounded-xl p-5 border border-slate-700">
        <h2 className="text-lg font-semibold text-white mb-4">Mode Control</h2>
        <div className="flex flex-wrap items-center gap-3">
          {(['nominal', 'safe', 'standby'] as SatelliteMode[]).map((mode) => (
            <button
              key={mode}
              onClick={() => modeMutation.mutate(mode)}
              disabled={displayData.mode === mode || modeMutation.isPending}
              className={`px-6 py-3 rounded-lg font-medium transition-colors ${
                displayData.mode === mode
                  ? 'bg-stellar-600 text-white cursor-default'
                  : 'bg-slate-700 text-slate-300 hover:bg-slate-600 hover:text-white'
              } disabled:opacity-50`}
            >
              Set {mode.charAt(0).toUpperCase() + mode.slice(1)}
            </button>
          ))}
        </div>
        {modeMutation.isPending && (
          <p className="text-stellar-400 text-sm mt-2">Updating mode...</p>
        )}
        {modeMutation.error && (
          <p className="text-red-400 text-sm mt-2">
            Error: {(modeMutation.error as Error).message}
          </p>
        )}
      </div>

      {/* Energy & Memory Bars */}
      <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
        <div className="bg-slate-800 rounded-xl p-5 border border-slate-700">
          <div className="flex items-center justify-between mb-3">
            <h3 className="text-lg font-semibold text-white">Energy Level</h3>
            <span className="text-2xl font-bold text-green-400">
              {Math.round(displayData.energy)}%
            </span>
          </div>
          <div className="w-full bg-slate-700 rounded-full h-4">
            <div
              className={`h-4 rounded-full transition-all duration-500 ${
                displayData.energy > 50
                  ? 'bg-gradient-to-r from-green-500 to-green-400'
                  : displayData.energy > 20
                  ? 'bg-gradient-to-r from-yellow-500 to-yellow-400'
                  : 'bg-gradient-to-r from-red-500 to-red-400'
              }`}
              style={{ width: `${Math.min(100, Math.max(0, displayData.energy))}%` }}
            />
          </div>
        </div>

        <div className="bg-slate-800 rounded-xl p-5 border border-slate-700">
          <div className="flex items-center justify-between mb-3">
            <h3 className="text-lg font-semibold text-white">Memory Usage</h3>
            <span className="text-2xl font-bold text-yellow-400">
              {Math.round(displayData.memory)}%
            </span>
          </div>
          <div className="w-full bg-slate-700 rounded-full h-4">
            <div
              className={`h-4 rounded-full transition-all duration-500 ${
                displayData.memory < 50
                  ? 'bg-gradient-to-r from-green-500 to-green-400'
                  : displayData.memory < 80
                  ? 'bg-gradient-to-r from-yellow-500 to-yellow-400'
                  : 'bg-gradient-to-r from-red-500 to-red-400'
              }`}
              style={{ width: `${Math.min(100, Math.max(0, displayData.memory))}%` }}
            />
          </div>
        </div>
      </div>

      {/* Telemetry Chart */}
      <TelemetryChart
        data={telemetryData}
        title="Telemetry History"
        height={300}
      />

      {/* Position Info (if available) */}
      {(displayData.latitude !== undefined || displayData.longitude !== undefined) && (
        <div className="bg-slate-800 rounded-xl p-5 border border-slate-700">
          <h2 className="text-lg font-semibold text-white mb-4">Position</h2>
          <div className="grid grid-cols-3 gap-4">
            <div>
              <span className="text-slate-400 text-sm">Latitude</span>
              <div className="text-white font-mono text-lg">
                {displayData.latitude?.toFixed(4) || 'N/A'}°
              </div>
            </div>
            <div>
              <span className="text-slate-400 text-sm">Longitude</span>
              <div className="text-white font-mono text-lg">
                {displayData.longitude?.toFixed(4) || 'N/A'}°
              </div>
            </div>
            <div>
              <span className="text-slate-400 text-sm">Altitude</span>
              <div className="text-white font-mono text-lg">
                {displayData.altitude?.toFixed(1) || 'N/A'} km
              </div>
            </div>
          </div>
        </div>
      )}

      {/* Metadata */}
      {(displayData.inserted_at || displayData.updated_at) && (
        <div className="bg-slate-800 rounded-xl p-5 border border-slate-700">
          <h2 className="text-lg font-semibold text-white mb-4">Metadata</h2>
          <div className="grid grid-cols-2 gap-4 text-sm">
            {displayData.inserted_at && (
              <div>
                <span className="text-slate-400">Created:</span>
                <span className="text-white ml-2">
                  {new Date(displayData.inserted_at).toLocaleString()}
                </span>
              </div>
            )}
            {displayData.updated_at && (
              <div>
                <span className="text-slate-400">Last Updated:</span>
                <span className="text-white ml-2">
                  {new Date(displayData.updated_at).toLocaleString()}
                </span>
              </div>
            )}
          </div>
        </div>
      )}
    </div>
  )
}
