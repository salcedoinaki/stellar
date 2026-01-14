import { useEffect } from 'react'
import { useQuery } from '@tanstack/react-query'
import { Link } from 'react-router-dom'
import { api } from '../services/api'
import { useSatelliteStore } from '../store/satelliteStore'
import { SatelliteCard, StatCard, TelemetryChart } from '../components'
import type { SatelliteMode } from '../types'

export default function Dashboard() {
  const { satellites, setSatellites, telemetryHistory } = useSatelliteStore()

  // Fetch satellites
  const { data: satelliteList, isLoading, error } = useQuery({
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

  const satelliteArray = Array.from(satellites.values())

  // Calculate stats
  const totalSatellites = satelliteArray.length
  const nominalCount = satelliteArray.filter((s) => s.mode === 'nominal').length
  const safeCount = satelliteArray.filter((s) => s.mode === 'safe').length
  const criticalCount = satelliteArray.filter((s) => s.mode === 'critical').length
  const avgEnergy = totalSatellites > 0
    ? satelliteArray.reduce((sum, s) => sum + s.energy, 0) / totalSatellites
    : 0
  const avgMemory = totalSatellites > 0
    ? satelliteArray.reduce((sum, s) => sum + s.memory, 0) / totalSatellites
    : 0

  // Get combined telemetry for chart
  const combinedTelemetry = Array.from(telemetryHistory.values())
    .flat()
    .sort((a, b) => a.timestamp - b.timestamp)
    .slice(-50)

  // Mode distribution for chart
  const modeDistribution: Record<SatelliteMode, number> = {
    nominal: nominalCount,
    safe: safeCount,
    critical: criticalCount,
    standby: satelliteArray.filter((s) => s.mode === 'standby').length,
  }

  if (isLoading) {
    return (
      <div className="flex items-center justify-center h-96">
        <div className="text-stellar-400 text-lg">Loading constellation data...</div>
      </div>
    )
  }

  if (error) {
    return (
      <div className="flex items-center justify-center h-96">
        <div className="text-red-400 text-lg">
          Error loading data: {(error as Error).message}
        </div>
      </div>
    )
  }

  return (
    <div className="space-y-6">
      {/* Header */}
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-3xl font-bold text-white">Mission Control</h1>
          <p className="text-slate-400 mt-1">
            Constellation overview and real-time monitoring
          </p>
        </div>
        <Link
          to="/satellites"
          className="px-4 py-2 bg-stellar-600 hover:bg-stellar-500 text-white rounded-lg transition-colors"
        >
          View All Satellites
        </Link>
      </div>

      {/* Stats Grid */}
      <div className="grid grid-cols-2 md:grid-cols-4 lg:grid-cols-6 gap-4">
        <StatCard label="Total Satellites" value={totalSatellites} color="blue" />
        <StatCard label="Nominal" value={nominalCount} color="green" />
        <StatCard label="Safe Mode" value={safeCount} color="yellow" />
        <StatCard label="Critical" value={criticalCount} color="red" />
        <StatCard
          label="Avg Energy"
          value={avgEnergy.toFixed(1)}
          unit="%"
          color={avgEnergy > 50 ? 'green' : avgEnergy > 20 ? 'yellow' : 'red'}
        />
        <StatCard
          label="Avg Memory"
          value={avgMemory.toFixed(1)}
          unit="%"
          color={avgMemory < 50 ? 'green' : avgMemory < 80 ? 'yellow' : 'red'}
        />
      </div>

      {/* Mode Distribution */}
      <div className="bg-slate-800 rounded-xl p-5 border border-slate-700">
        <h2 className="text-lg font-semibold text-white mb-4">Mode Distribution</h2>
        <div className="flex items-end gap-4 h-32">
          {Object.entries(modeDistribution).map(([mode, count]) => {
            const maxCount = Math.max(...Object.values(modeDistribution), 1)
            const height = (count / maxCount) * 100
            const colors: Record<string, string> = {
              nominal: 'bg-green-500',
              safe: 'bg-yellow-500',
              critical: 'bg-red-500',
              standby: 'bg-blue-500',
            }
            return (
              <div key={mode} className="flex-1 flex flex-col items-center">
                <div className="text-sm text-white mb-1">{count}</div>
                <div
                  className={`w-full ${colors[mode]} rounded-t transition-all duration-500`}
                  style={{ height: `${height}%`, minHeight: count > 0 ? '8px' : '2px' }}
                />
                <div className="text-xs text-slate-400 mt-2 capitalize">{mode}</div>
              </div>
            )
          })}
        </div>
      </div>

      {/* Telemetry Chart */}
      <TelemetryChart
        data={combinedTelemetry}
        title="Constellation Telemetry"
        height={250}
      />

      {/* Recent Satellites */}
      {satelliteArray.length > 0 && (
        <div>
          <h2 className="text-lg font-semibold text-white mb-4">Active Satellites</h2>
          <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4 gap-4">
            {satelliteArray.slice(0, 8).map((satellite) => (
              <SatelliteCard key={satellite.id} satellite={satellite} />
            ))}
          </div>
        </div>
      )}

      {/* Empty state */}
      {satelliteArray.length === 0 && (
        <div className="bg-slate-800 rounded-xl p-12 border border-slate-700 text-center">
          <div className="text-4xl mb-4">🛰️</div>
          <h3 className="text-xl font-semibold text-white mb-2">No Satellites</h3>
          <p className="text-slate-400 mb-4">
            No satellites are currently being tracked. Start by adding a satellite.
          </p>
          <Link
            to="/satellites"
            className="inline-block px-4 py-2 bg-stellar-600 hover:bg-stellar-500 text-white rounded-lg transition-colors"
          >
            Add Satellite
          </Link>
        </div>
      )}
    </div>
  )
}
