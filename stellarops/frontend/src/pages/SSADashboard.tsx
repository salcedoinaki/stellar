import { useEffect, useState, useCallback } from 'react'
import { useSSAStore } from '../store/ssaStore'
import { useSSAChannel } from '../hooks/useSSAChannel'
import { ThreatMap } from '../components/ThreatMap'
import { ConjunctionCard } from '../components/ConjunctionCard'
import type { Conjunction } from '../types'

export function SSADashboard() {
  const {
    spaceObjects,
    protectedAssets,
    conjunctions,
    criticalConjunctions,
    conjunctionStats,
    pendingCOAs,
    detectorStatus,
    isLoading,
    error,
    fetchSpaceObjects,
    fetchProtectedAssets,
    fetchConjunctions,
    fetchCriticalConjunctions,
    fetchConjunctionStats,
    fetchPendingCOAs,
    fetchDetectorStatus,
    triggerScreening,
    approveCOA,
    rejectCOA,
    clearError,
    selectConjunction,
  } = useSSAStore()

  const [selectedConjunctionId, setSelectedConjunctionId] = useState<string | null>(null)
  const [selectedObjectId, setSelectedObjectId] = useState<string | null>(null)
  const [activeTab, setActiveTab] = useState<'map' | 'list'>('map')
  const [refreshing, setRefreshing] = useState(false)

  // Real-time SSA event handlers
  const handleConjunctionDetected = useCallback((conjunction: Conjunction) => {
    console.log('[SSA] New conjunction detected:', conjunction.id)
    // Could show a notification here
  }, [])

  const handleScreeningComplete = useCallback((results: { found: number; screened: number }) => {
    console.log('[SSA] Screening complete:', results)
    // Refresh data after screening
    fetchCriticalConjunctions()
    fetchConjunctionStats()
  }, [fetchCriticalConjunctions, fetchConjunctionStats])

  // Subscribe to SSA WebSocket channel for real-time updates
  const { triggerScreening: wsScreening } = useSSAChannel({
    onConjunctionDetected: handleConjunctionDetected,
    onScreeningComplete: handleScreeningComplete,
  })

  // Initial data load
  useEffect(() => {
    loadAllData()
    // Set up periodic refresh every 30 seconds (as fallback to WebSocket)
    const interval = setInterval(loadAllData, 30000)
    return () => clearInterval(interval)
  }, [])

  const loadAllData = async () => {
    await Promise.all([
      fetchSpaceObjects({ limit: 500 }),
      fetchProtectedAssets(),
      fetchConjunctions({ upcoming: true, limit: 100 }),
      fetchCriticalConjunctions(),
      fetchConjunctionStats(),
      fetchPendingCOAs(),
      fetchDetectorStatus(),
    ])
  }

  const handleRefresh = async () => {
    setRefreshing(true)
    await loadAllData()
    setRefreshing(false)
  }

  const handleTriggerScreening = async () => {
    await triggerScreening()
    // Show notification
  }

  const handleSelectConjunction = (id: string) => {
    setSelectedConjunctionId(id)
    selectConjunction(id)
  }

  const handleApproveCOA = async (coaId: string) => {
    await approveCOA(coaId, 'operator')
  }

  const handleRejectCOA = async (coaId: string) => {
    await rejectCOA(coaId, 'operator')
  }

  const selectedConjunction = conjunctions.find(c => c.id === selectedConjunctionId) ||
                               criticalConjunctions.find(c => c.id === selectedConjunctionId)

  // Group conjunctions by timeframe
  const next24h = conjunctions.filter(c => {
    const hours = (new Date(c.tca).getTime() - Date.now()) / (1000 * 60 * 60)
    return hours > 0 && hours <= 24
  })
  const next7d = conjunctions.filter(c => {
    const hours = (new Date(c.tca).getTime() - Date.now()) / (1000 * 60 * 60)
    return hours > 24 && hours <= 168
  })

  return (
    <div className="min-h-screen bg-slate-950 text-white p-6">
      {/* Header */}
      <div className="flex justify-between items-center mb-6">
        <div>
          <h1 className="text-2xl font-bold">Space Situational Awareness</h1>
          <p className="text-gray-400 text-sm">
            Tracking {spaceObjects.length} objects • {protectedAssets.length} protected assets
          </p>
        </div>
        <div className="flex items-center gap-4">
          {/* Detector Status */}
          <div className="flex items-center gap-2 text-sm">
            <div className={`w-2 h-2 rounded-full ${detectorStatus?.screening_in_progress ? 'bg-yellow-400 animate-pulse' : 'bg-green-400'}`} />
            <span className="text-gray-400">
              {detectorStatus?.screening_in_progress 
                ? 'Screening...' 
                : detectorStatus?.last_screening_at 
                  ? `Last scan: ${new Date(detectorStatus.last_screening_at).toLocaleTimeString()}`
                  : 'Ready'
              }
            </span>
          </div>
          
          <button
            onClick={handleTriggerScreening}
            disabled={detectorStatus?.screening_in_progress}
            className="px-4 py-2 bg-purple-600 hover:bg-purple-500 disabled:bg-gray-600 rounded-lg text-sm font-medium transition-colors"
          >
            Run Screening
          </button>
          
          <button
            onClick={handleRefresh}
            disabled={refreshing}
            className="px-4 py-2 bg-slate-700 hover:bg-slate-600 rounded-lg text-sm font-medium transition-colors"
          >
            {refreshing ? 'Refreshing...' : 'Refresh'}
          </button>
        </div>
      </div>

      {/* Error banner */}
      {error && (
        <div className="mb-4 bg-red-900/50 border border-red-500 rounded-lg p-4 flex justify-between items-center">
          <span className="text-red-300">{error}</span>
          <button onClick={clearError} className="text-red-400 hover:text-red-300">✕</button>
        </div>
      )}

      {/* Stats Row */}
      <div className="grid grid-cols-5 gap-4 mb-6">
        <StatCard
          title="Critical Conjunctions"
          value={conjunctionStats?.critical_next_24h || 0}
          subtitle="Next 24h"
          variant="critical"
        />
        <StatCard
          title="High Risk Events"
          value={conjunctionStats?.critical_next_7d || 0}
          subtitle="Next 7 days"
          variant="warning"
        />
        <StatCard
          title="Total Upcoming"
          value={conjunctionStats?.total_upcoming || 0}
          subtitle="All severities"
          variant="info"
        />
        <StatCard
          title="Pending Decisions"
          value={pendingCOAs.length}
          subtitle="COAs to review"
          variant={pendingCOAs.length > 0 ? 'warning' : 'success'}
        />
        <StatCard
          title="Maneuvers Pending"
          value={conjunctionStats?.maneuvers_pending || 0}
          subtitle="Approved COAs"
          variant="info"
        />
      </div>

      {/* Main content grid */}
      <div className="grid grid-cols-12 gap-6">
        {/* Left: Map/List view */}
        <div className="col-span-8">
          {/* Tabs */}
          <div className="flex gap-2 mb-4">
            <button
              onClick={() => setActiveTab('map')}
              className={`px-4 py-2 rounded-lg text-sm font-medium transition-colors ${
                activeTab === 'map' 
                  ? 'bg-blue-600 text-white' 
                  : 'bg-slate-800 text-gray-400 hover:bg-slate-700'
              }`}
            >
              Threat Map
            </button>
            <button
              onClick={() => setActiveTab('list')}
              className={`px-4 py-2 rounded-lg text-sm font-medium transition-colors ${
                activeTab === 'list' 
                  ? 'bg-blue-600 text-white' 
                  : 'bg-slate-800 text-gray-400 hover:bg-slate-700'
              }`}
            >
              Conjunction List
            </button>
          </div>

          {/* Content */}
          {activeTab === 'map' ? (
            <div className="h-[600px] bg-slate-900 rounded-xl overflow-hidden">
              <ThreatMap
                spaceObjects={spaceObjects}
                conjunctions={criticalConjunctions}
                protectedAssets={protectedAssets}
                selectedObjectId={selectedObjectId}
                selectedConjunctionId={selectedConjunctionId}
                onSelectObject={setSelectedObjectId}
                onSelectConjunction={handleSelectConjunction}
              />
            </div>
          ) : (
            <div className="bg-slate-900 rounded-xl p-4">
              {/* Next 24h */}
              {next24h.length > 0 && (
                <div className="mb-6">
                  <h3 className="text-lg font-semibold mb-3 flex items-center gap-2">
                    <span className="w-2 h-2 rounded-full bg-red-500 animate-pulse" />
                    Next 24 Hours ({next24h.length})
                  </h3>
                  <div className="space-y-3">
                    {next24h.map(conj => (
                      <ConjunctionCard
                        key={conj.id}
                        conjunction={conj}
                        compact
                        isSelected={conj.id === selectedConjunctionId}
                        onSelect={() => handleSelectConjunction(conj.id)}
                      />
                    ))}
                  </div>
                </div>
              )}

              {/* Next 7 days */}
              {next7d.length > 0 && (
                <div>
                  <h3 className="text-lg font-semibold mb-3">
                    Next 7 Days ({next7d.length})
                  </h3>
                  <div className="space-y-3">
                    {next7d.map(conj => (
                      <ConjunctionCard
                        key={conj.id}
                        conjunction={conj}
                        compact
                        isSelected={conj.id === selectedConjunctionId}
                        onSelect={() => handleSelectConjunction(conj.id)}
                      />
                    ))}
                  </div>
                </div>
              )}

              {conjunctions.length === 0 && (
                <div className="text-center py-12 text-gray-500">
                  No upcoming conjunctions detected
                </div>
              )}
            </div>
          )}
        </div>

        {/* Right: Details panel */}
        <div className="col-span-4 space-y-6">
          {/* Selected conjunction details */}
          {selectedConjunction ? (
            <div>
              <h3 className="text-lg font-semibold mb-3">Conjunction Details</h3>
              <ConjunctionCard
                conjunction={selectedConjunction}
                coas={pendingCOAs.filter(c => c.conjunction_id === selectedConjunction.id)}
                onApproveCOA={handleApproveCOA}
                onRejectCOA={handleRejectCOA}
              />
            </div>
          ) : (
            <div className="bg-slate-900 rounded-xl p-6 text-center text-gray-500">
              <p>Select a conjunction to view details</p>
            </div>
          )}

          {/* Critical alerts */}
          {criticalConjunctions.length > 0 && (
            <div>
              <h3 className="text-lg font-semibold mb-3 flex items-center gap-2">
                <span className="text-red-500">⚠</span>
                Critical Alerts
              </h3>
              <div className="space-y-2">
                {criticalConjunctions.slice(0, 5).map(conj => (
                  <div
                    key={conj.id}
                    onClick={() => handleSelectConjunction(conj.id)}
                    className="bg-red-900/30 border border-red-500/50 rounded-lg p-3 cursor-pointer hover:bg-red-900/50 transition-colors"
                  >
                    <div className="flex justify-between items-center">
                      <div className="text-sm font-medium truncate flex-1">
                        {conj.primary_object?.name || 'Asset'} ↔ {conj.secondary_object?.name || 'Object'}
                      </div>
                      <div className="text-red-400 font-bold text-sm">
                        {formatTimeToTca(conj.tca)}
                      </div>
                    </div>
                    <div className="text-xs text-gray-400 mt-1">
                      Miss: {formatMissDistance(conj.miss_distance.total_m)}
                      {conj.collision_probability && ` • Pc: ${conj.collision_probability.toExponential(1)}`}
                    </div>
                  </div>
                ))}
              </div>
            </div>
          )}

          {/* Pending COA Decisions */}
          {pendingCOAs.length > 0 && (
            <div>
              <h3 className="text-lg font-semibold mb-3">Pending Decisions</h3>
              <div className="space-y-2">
                {pendingCOAs.slice(0, 5).map(coa => (
                  <div
                    key={coa.id}
                    className="bg-amber-900/30 border border-amber-500/50 rounded-lg p-3"
                  >
                    <div className="flex justify-between items-center mb-2">
                      <span className="text-sm font-medium text-white">{coa.title}</span>
                      <span className={`text-xs px-2 py-1 rounded ${
                        coa.priority === 'critical' ? 'bg-red-500/20 text-red-400' :
                        coa.priority === 'high' ? 'bg-orange-500/20 text-orange-400' :
                        'bg-gray-500/20 text-gray-400'
                      }`}>
                        {coa.priority}
                      </span>
                    </div>
                    <div className="text-xs text-gray-400 mb-2">
                      {coa.coa_type.replace('_', ' ')}
                      {coa.maneuver.delta_v_ms && ` • ΔV: ${coa.maneuver.delta_v_ms.toFixed(2)} m/s`}
                    </div>
                    <div className="flex gap-2">
                      <button
                        onClick={() => handleApproveCOA(coa.id)}
                        className="flex-1 py-1 bg-green-600 hover:bg-green-500 text-white text-xs rounded transition-colors"
                      >
                        Approve
                      </button>
                      <button
                        onClick={() => handleRejectCOA(coa.id)}
                        className="flex-1 py-1 bg-slate-600 hover:bg-slate-500 text-white text-xs rounded transition-colors"
                      >
                        Reject
                      </button>
                    </div>
                  </div>
                ))}
              </div>
            </div>
          )}
        </div>
      </div>
    </div>
  )
}

// Helper components
function StatCard({ 
  title, 
  value, 
  subtitle, 
  variant = 'default' 
}: { 
  title: string
  value: number | string
  subtitle: string
  variant?: 'default' | 'critical' | 'warning' | 'success' | 'info'
}) {
  const variantStyles = {
    default: 'bg-slate-800 border-slate-700',
    critical: 'bg-red-900/30 border-red-500/50',
    warning: 'bg-amber-900/30 border-amber-500/50',
    success: 'bg-green-900/30 border-green-500/50',
    info: 'bg-blue-900/30 border-blue-500/50',
  }

  const valueColors = {
    default: 'text-white',
    critical: 'text-red-400',
    warning: 'text-amber-400',
    success: 'text-green-400',
    info: 'text-blue-400',
  }

  return (
    <div className={`rounded-xl border p-4 ${variantStyles[variant]}`}>
      <div className="text-sm text-gray-400 mb-1">{title}</div>
      <div className={`text-3xl font-bold ${valueColors[variant]}`}>{value}</div>
      <div className="text-xs text-gray-500">{subtitle}</div>
    </div>
  )
}

// Helper functions
function formatTimeToTca(tca: string): string {
  const hours = (new Date(tca).getTime() - Date.now()) / (1000 * 60 * 60)
  if (hours <= 0) return 'PASSED'
  if (hours < 1) return `${Math.floor(hours * 60)}m`
  if (hours < 24) return `${Math.floor(hours)}h`
  return `${Math.floor(hours / 24)}d`
}

function formatMissDistance(meters: number): string {
  if (meters >= 1000) return `${(meters / 1000).toFixed(2)} km`
  return `${meters.toFixed(0)} m`
}

export default SSADashboard
