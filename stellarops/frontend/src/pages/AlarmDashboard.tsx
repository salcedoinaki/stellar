import { useEffect, useState, useCallback } from 'react'
import { useSatelliteStore } from '../store/satelliteStore'
import { api, type AlarmFilters } from '../services/api'
import type { Alarm, AlarmSeverity, AlarmStatus } from '../types'

type SortField = 'severity' | 'triggered_at' | 'status' | 'source'
type SortOrder = 'asc' | 'desc'

export default function AlarmDashboard() {
  const { isConnected } = useSatelliteStore()
  
  const [alarms, setAlarms] = useState<Alarm[]>([])
  const [selectedAlarm, setSelectedAlarm] = useState<Alarm | null>(null)
  const [isLoading, setIsLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)
  const [filters, setFilters] = useState<AlarmFilters>({})
  const [sortField, setSortField] = useState<SortField>('triggered_at')
  const [sortOrder, setSortOrder] = useState<SortOrder>('desc')
  const [selectedIds, setSelectedIds] = useState<Set<string>>(new Set())
  const [showDetailModal, setShowDetailModal] = useState(false)
  const [showAcknowledged, setShowAcknowledged] = useState(true)
  
  // Stats
  const alarmCounts = {
    critical: alarms.filter(a => a.severity === 'critical' && a.status === 'active').length,
    high: alarms.filter(a => a.severity === 'high' && a.status === 'active').length,
    medium: alarms.filter(a => a.severity === 'medium' && a.status === 'active').length,
    low: alarms.filter(a => a.severity === 'low' && a.status === 'active').length,
    info: alarms.filter(a => a.severity === 'info' && a.status === 'active').length,
    warning: alarms.filter(a => a.severity === 'warning' && a.status === 'active').length,
  }
  const activeCount = alarms.filter(a => a.status === 'active').length
  const acknowledgedCount = alarms.filter(a => a.status === 'acknowledged').length

  // Fetch alarms
  const fetchAlarms = useCallback(async () => {
    try {
      setIsLoading(true)
      const data = await api.alarms.list(filters)
      setAlarms(data)
      setError(null)
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to fetch alarms')
    } finally {
      setIsLoading(false)
    }
  }, [filters])

  useEffect(() => {
    fetchAlarms()
    // Auto-refresh every 10 seconds
    const interval = setInterval(fetchAlarms, 10000)
    return () => clearInterval(interval)
  }, [fetchAlarms])

  // Sort and filter alarms
  const filteredAlarms = alarms.filter((alarm) => {
    if (!showAcknowledged && alarm.status === 'acknowledged') return false
    return true
  })

  const sortedAlarms = [...filteredAlarms].sort((a, b) => {
    let comparison = 0
    switch (sortField) {
      case 'severity':
        const severityOrder: Record<string, number> = { critical: 0, high: 1, warning: 2, medium: 3, low: 4, info: 5 }
        comparison = (severityOrder[a.severity] ?? 6) - (severityOrder[b.severity] ?? 6)
        break
      case 'triggered_at':
        comparison = new Date(a.triggered_at || a.inserted_at).getTime() - new Date(b.triggered_at || b.inserted_at).getTime()
        break
      case 'status':
        const statusOrder: Record<string, number> = { active: 0, acknowledged: 1, resolved: 2 }
        comparison = (statusOrder[a.status] ?? 3) - (statusOrder[b.status] ?? 3)
        break
      case 'source':
        comparison = (a.source || '').localeCompare(b.source || '')
        break
    }
    return sortOrder === 'asc' ? comparison : -comparison
  })

  // Handle acknowledge
  const handleAcknowledge = async (alarmId: string) => {
    try {
      await api.alarms.acknowledge(alarmId)
      fetchAlarms()
    } catch (err) {
      console.error('Failed to acknowledge alarm:', err)
    }
  }

  // Handle resolve
  const handleResolve = async (alarmId: string, resolution?: string) => {
    try {
      await api.alarms.resolve(alarmId, resolution)
      fetchAlarms()
      if (selectedAlarm?.id === alarmId) setSelectedAlarm(null)
    } catch (err) {
      console.error('Failed to resolve alarm:', err)
    }
  }

  // Bulk acknowledge
  const handleBulkAcknowledge = async () => {
    try {
      await Promise.all([...selectedIds].map(id => api.alarms.acknowledge(id)))
      setSelectedIds(new Set())
      fetchAlarms()
    } catch (err) {
      console.error('Failed to bulk acknowledge:', err)
    }
  }

  // Bulk resolve
  const handleBulkResolve = async () => {
    try {
      await Promise.all([...selectedIds].map(id => api.alarms.resolve(id)))
      setSelectedIds(new Set())
      fetchAlarms()
    } catch (err) {
      console.error('Failed to bulk resolve:', err)
    }
  }

  // Toggle selection
  const toggleSelection = (id: string) => {
    const newSet = new Set(selectedIds)
    if (newSet.has(id)) {
      newSet.delete(id)
    } else {
      newSet.add(id)
    }
    setSelectedIds(newSet)
  }

  // Select all visible
  const selectAllVisible = () => {
    setSelectedIds(new Set(sortedAlarms.map(a => a.id)))
  }

  // Clear selection
  const clearSelection = () => {
    setSelectedIds(new Set())
  }

  const getSeverityColor = (severity: AlarmSeverity) => {
    switch (severity) {
      case 'critical': return 'bg-red-500/20 border-red-500 text-red-400'
      case 'high': return 'bg-orange-500/20 border-orange-500 text-orange-400'
      case 'warning': return 'bg-yellow-500/20 border-yellow-500 text-yellow-400'
      case 'medium': return 'bg-yellow-500/20 border-yellow-500 text-yellow-400'
      case 'low': return 'bg-blue-500/20 border-blue-500 text-blue-400'
      case 'info': return 'bg-slate-500/20 border-slate-500 text-slate-400'
      default: return 'bg-slate-500/20 border-slate-500 text-slate-400'
    }
  }

  const getStatusBadge = (status: AlarmStatus) => {
    switch (status) {
      case 'active': return <span className="px-2 py-0.5 bg-red-500/20 text-red-400 text-xs rounded">Active</span>
      case 'acknowledged': return <span className="px-2 py-0.5 bg-yellow-500/20 text-yellow-400 text-xs rounded">Acknowledged</span>
      case 'resolved': return <span className="px-2 py-0.5 bg-green-500/20 text-green-400 text-xs rounded">Resolved</span>
      default: return null
    }
  }

  const formatTime = (dateStr: string) => {
    const date = new Date(dateStr)
    return date.toLocaleString()
  }

  const formatTimeAgo = (dateStr: string) => {
    const date = new Date(dateStr)
    const now = new Date()
    const diffMs = now.getTime() - date.getTime()
    const diffMins = Math.floor(diffMs / 60000)
    const diffHours = Math.floor(diffMs / 3600000)
    const diffDays = Math.floor(diffMs / 86400000)

    if (diffMins < 1) return 'just now'
    if (diffMins < 60) return `${diffMins}m ago`
    if (diffHours < 24) return `${diffHours}h ago`
    return `${diffDays}d ago`
  }

  return (
    <div className="space-y-6">
      {/* Header */}
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-bold text-white">Alarm Dashboard</h1>
          <p className="text-slate-400 text-sm mt-1">
            Monitor and manage system alarms
          </p>
        </div>
        <div className="flex items-center gap-3">
          <button
            onClick={fetchAlarms}
            disabled={isLoading}
            className="px-4 py-2 bg-slate-700 hover:bg-slate-600 text-white text-sm rounded-lg transition-colors flex items-center gap-2"
          >
            <span className={isLoading ? 'animate-spin' : ''}></span>
            Refresh
          </button>
        </div>
      </div>

      {/* Summary Cards */}
      <div className="flex gap-4">
        <SummaryCard label="Critical" count={alarmCounts.critical} color="red" />
        <SummaryCard label="High" count={alarmCounts.high} color="orange" />
        <SummaryCard label="Warning" count={alarmCounts.warning + alarmCounts.medium} color="yellow" />
        <SummaryCard label="Low" count={alarmCounts.low} color="blue" />
        <SummaryCard label="Info" count={alarmCounts.info} color="slate" />
      </div>

      {/* Filters & Actions Bar */}
      <div className="bg-slate-800 rounded-lg p-4 flex items-center justify-between flex-wrap gap-4">
        <div className="flex items-center gap-3">
          {/* Severity Filter */}
          <select
            value={filters.severity || ''}
            onChange={(e) => setFilters({ ...filters, severity: e.target.value as AlarmSeverity || undefined })}
            className="bg-slate-700 border border-slate-600 text-white text-sm rounded-lg px-3 py-2"
          >
            <option value="">All Severities</option>
            <option value="critical">Critical</option>
            <option value="high">High</option>
            <option value="warning">Warning</option>
            <option value="medium">Medium</option>
            <option value="low">Low</option>
            <option value="info">Info</option>
          </select>

          {/* Status Filter */}
          <select
            value={filters.status || ''}
            onChange={(e) => setFilters({ ...filters, status: e.target.value as AlarmStatus || undefined })}
            className="bg-slate-700 border border-slate-600 text-white text-sm rounded-lg px-3 py-2"
          >
            <option value="">All Statuses</option>
            <option value="active">Active</option>
            <option value="acknowledged">Acknowledged</option>
            <option value="resolved">Resolved</option>
          </select>

          {/* Sort */}
          <select
            value={sortField}
            onChange={(e) => setSortField(e.target.value as SortField)}
            className="bg-slate-700 border border-slate-600 text-white text-sm rounded-lg px-3 py-2"
          >
            <option value="triggered_at">Sort by Time</option>
            <option value="severity">Sort by Severity</option>
            <option value="status">Sort by Status</option>
            <option value="source">Sort by Source</option>
          </select>

          <button
            onClick={() => setSortOrder(sortOrder === 'asc' ? 'desc' : 'asc')}
            className="p-2 bg-slate-700 hover:bg-slate-600 text-white rounded-lg"
          >
            {sortOrder === 'asc' ? '' : ''}
          </button>

          <label className="flex items-center gap-2 text-sm text-slate-400">
            <input
              type="checkbox"
              checked={showAcknowledged}
              onChange={(e) => setShowAcknowledged(e.target.checked)}
              className="rounded border-slate-600"
            />
            Show Acknowledged
          </label>
        </div>

        {/* Bulk Actions */}
        <div className="flex items-center gap-2">
          {selectedIds.size > 0 && (
            <>
              <span className="text-slate-400 text-sm">{selectedIds.size} selected</span>
              <button
                onClick={handleBulkAcknowledge}
                className="px-3 py-1.5 bg-yellow-600 hover:bg-yellow-500 text-white text-sm rounded-lg"
              >
                Acknowledge Selected
              </button>
              <button
                onClick={handleBulkResolve}
                className="px-3 py-1.5 bg-green-600 hover:bg-green-500 text-white text-sm rounded-lg"
              >
                Resolve Selected
              </button>
              <button
                onClick={clearSelection}
                className="px-3 py-1.5 bg-slate-600 hover:bg-slate-500 text-white text-sm rounded-lg"
              >
                Clear
              </button>
            </>
          )}
          {selectedIds.size === 0 && (
            <button
              onClick={selectAllVisible}
              className="px-3 py-1.5 bg-slate-600 hover:bg-slate-500 text-white text-sm rounded-lg"
            >
              Select All
            </button>
          )}
        </div>
      </div>

      {/* Error Display */}
      {error && (
        <div className="bg-red-500/20 border border-red-500/50 text-red-400 px-4 py-3 rounded-lg">
          {error}
        </div>
      )}

      {/* Alarm List */}
      <div className="bg-slate-800 rounded-lg overflow-hidden">
        {isLoading && alarms.length === 0 ? (
          <div className="p-8 text-center text-slate-400">
            Loading alarms...
          </div>
        ) : sortedAlarms.length === 0 ? (
          <div className="p-8 text-center text-slate-400">
            No alarms found
          </div>
        ) : (
          <table className="w-full">
            <thead className="bg-slate-700">
              <tr>
                <th className="px-4 py-3 text-left text-xs font-medium text-slate-400 uppercase">
                  <input
                    type="checkbox"
                    checked={selectedIds.size === sortedAlarms.length && sortedAlarms.length > 0}
                    onChange={(e) => e.target.checked ? selectAllVisible() : clearSelection()}
                    className="rounded bg-slate-600 border-slate-500"
                  />
                </th>
                <th className="px-4 py-3 text-left text-xs font-medium text-slate-400 uppercase">Severity</th>
                <th className="px-4 py-3 text-left text-xs font-medium text-slate-400 uppercase">Message</th>
                <th className="px-4 py-3 text-left text-xs font-medium text-slate-400 uppercase">Source</th>
                <th className="px-4 py-3 text-left text-xs font-medium text-slate-400 uppercase">Status</th>
                <th className="px-4 py-3 text-left text-xs font-medium text-slate-400 uppercase">Time</th>
                <th className="px-4 py-3 text-left text-xs font-medium text-slate-400 uppercase">Actions</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-slate-700">
              {sortedAlarms.map((alarm) => (
                <tr 
                  key={alarm.id} 
                  className={`hover:bg-slate-700/50 cursor-pointer ${
                    selectedAlarm?.id === alarm.id ? 'bg-stellar-600/20' : ''
                  }`}
                  onClick={() => {
                    setSelectedAlarm(alarm)
                    setShowDetailModal(true)
                  }}
                >
                  <td className="px-4 py-3" onClick={(e) => e.stopPropagation()}>
                    <input
                      type="checkbox"
                      checked={selectedIds.has(alarm.id)}
                      onChange={() => toggleSelection(alarm.id)}
                      className="rounded bg-slate-600 border-slate-500"
                    />
                  </td>
                  <td className="px-4 py-3">
                    <span className={`inline-flex items-center px-2 py-1 rounded text-xs font-medium border ${getSeverityColor(alarm.severity)}`}>
                      <SeverityIndicator severity={alarm.severity} pulsate={alarm.status === 'active'} />
                      <span className="ml-2">{alarm.severity}</span>
                    </span>
                  </td>
                  <td className="px-4 py-3 text-white max-w-md truncate">{alarm.title || alarm.message}</td>
                  <td className="px-4 py-3 text-slate-300">{alarm.source || 'System'}</td>
                  <td className="px-4 py-3">{getStatusBadge(alarm.status)}</td>
                  <td className="px-4 py-3 text-slate-400 text-sm" title={formatTime(alarm.triggered_at || alarm.inserted_at)}>
                    {formatTimeAgo(alarm.triggered_at || alarm.inserted_at)}
                  </td>
                  <td className="px-4 py-3" onClick={(e) => e.stopPropagation()}>
                    <div className="flex items-center gap-2">
                      {alarm.status === 'active' && (
                        <button
                          onClick={() => handleAcknowledge(alarm.id)}
                          className="px-2 py-1 bg-yellow-600 hover:bg-yellow-500 text-white text-xs rounded"
                        >
                          Ack
                        </button>
                      )}
                      {alarm.status !== 'resolved' && (
                        <button
                          onClick={() => handleResolve(alarm.id)}
                          className="px-2 py-1 bg-green-600 hover:bg-green-500 text-white text-xs rounded"
                        >
                          Resolve
                        </button>
                      )}
                    </div>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </div>

      {/* Detail Modal */}
      {showDetailModal && selectedAlarm && (
        <AlarmDetailModal
          alarm={selectedAlarm}
          onClose={() => setShowDetailModal(false)}
          onAcknowledge={() => {
            handleAcknowledge(selectedAlarm.id)
            setShowDetailModal(false)
          }}
          onResolve={(resolution) => {
            handleResolve(selectedAlarm.id, resolution)
            setShowDetailModal(false)
          }}
          getSeverityColor={getSeverityColor}
          getStatusBadge={getStatusBadge}
          formatTime={formatTime}
        />
      )}
    </div>
  )
}

// Summary Card Component
function SummaryCard({
  label,
  count,
  color,
}: {
  label: string
  count: number
  color: 'red' | 'orange' | 'yellow' | 'blue' | 'slate'
}) {
  const colors = {
    red: 'bg-red-500/10 border-red-500/50 text-red-400',
    orange: 'bg-orange-500/10 border-orange-500/50 text-orange-400',
    yellow: 'bg-yellow-500/10 border-yellow-500/50 text-yellow-400',
    blue: 'bg-blue-500/10 border-blue-500/50 text-blue-400',
    slate: 'bg-slate-700/50 border-slate-600 text-slate-400',
  }

  return (
    <div className={`flex-1 rounded-lg border p-4 ${colors[color]}`}>
      <div className="text-3xl font-bold">{count}</div>
      <div className="text-sm uppercase">{label}</div>
    </div>
  )
}

// Severity Indicator Component
function SeverityIndicator({
  severity,
  pulsate,
}: {
  severity: AlarmSeverity
  pulsate: boolean
}) {
  const colors: Record<string, string> = {
    critical: 'bg-red-500',
    high: 'bg-orange-500',
    warning: 'bg-yellow-500',
    medium: 'bg-yellow-500',
    low: 'bg-blue-500',
    info: 'bg-slate-500',
  }

  return (
    <div className={`w-2 h-2 rounded-full ${colors[severity] || 'bg-slate-500'} ${pulsate ? 'animate-pulse' : ''}`} />
  )
}

// Alarm Detail Modal Component
function AlarmDetailModal({
  alarm,
  onClose,
  onAcknowledge,
  onResolve,
  getSeverityColor,
  getStatusBadge,
  formatTime,
}: {
  alarm: Alarm
  onClose: () => void
  onAcknowledge: () => void
  onResolve: (resolution: string) => void
  getSeverityColor: (severity: AlarmSeverity) => string
  getStatusBadge: (status: AlarmStatus) => React.ReactNode
  formatTime: (dateStr: string) => string
}) {
  const [resolution, setResolution] = useState('')

  return (
    <div className="fixed inset-0 bg-black/50 flex items-center justify-center z-50 p-4">
      <div className="bg-slate-800 rounded-lg max-w-2xl w-full max-h-[80vh] overflow-auto">
        <div className="p-6">
          <div className="flex items-start justify-between mb-4">
            <div>
              <h2 className="text-xl font-bold text-white">Alarm Details</h2>
              <p className="text-slate-400 text-sm">ID: {alarm.id}</p>
            </div>
            <button
              onClick={onClose}
              className="text-slate-400 hover:text-white text-xl"
            >
              
            </button>
          </div>

          <div className="space-y-4">
            <div className="grid grid-cols-2 gap-4">
              <div>
                <label className="text-slate-400 text-sm">Severity</label>
                <div className={`mt-1 inline-flex items-center px-3 py-1 rounded border ${getSeverityColor(alarm.severity)}`}>
                  {alarm.severity}
                </div>
              </div>
              <div>
                <label className="text-slate-400 text-sm">Status</label>
                <div className="mt-1">{getStatusBadge(alarm.status)}</div>
              </div>
            </div>

            <div>
              <label className="text-slate-400 text-sm">Title</label>
              <p className="mt-1 text-white font-medium">{alarm.title || 'N/A'}</p>
            </div>

            <div>
              <label className="text-slate-400 text-sm">Message</label>
              <p className="mt-1 text-white">{alarm.message}</p>
            </div>

            <div className="grid grid-cols-2 gap-4">
              <div>
                <label className="text-slate-400 text-sm">Source</label>
                <p className="mt-1 text-white">{alarm.source || 'System'}</p>
              </div>
              <div>
                <label className="text-slate-400 text-sm">Satellite ID</label>
                <p className="mt-1 text-white">{alarm.satellite_id || 'N/A'}</p>
              </div>
            </div>

            <div className="grid grid-cols-3 gap-4">
              <div>
                <label className="text-slate-400 text-sm">Triggered</label>
                <p className="mt-1 text-white text-sm">{formatTime(alarm.triggered_at || alarm.inserted_at)}</p>
              </div>
              {alarm.acknowledged_at && (
                <div>
                  <label className="text-slate-400 text-sm">Acknowledged</label>
                  <p className="mt-1 text-white text-sm">{formatTime(alarm.acknowledged_at)}</p>
                </div>
              )}
              {alarm.resolved_at && (
                <div>
                  <label className="text-slate-400 text-sm">Resolved</label>
                  <p className="mt-1 text-white text-sm">{formatTime(alarm.resolved_at)}</p>
                </div>
              )}
            </div>

            {alarm.resolution && (
              <div className="bg-green-500/10 border border-green-500/50 rounded p-3">
                <label className="text-green-400 text-sm">Resolution</label>
                <p className="mt-1 text-white">{alarm.resolution}</p>
              </div>
            )}

            {(alarm.details || alarm.data) && Object.keys(alarm.details || alarm.data || {}).length > 0 && (
              <div>
                <label className="text-slate-400 text-sm">Details</label>
                <pre className="mt-1 bg-slate-900 text-slate-300 p-3 rounded text-sm overflow-auto max-h-48">
                  {JSON.stringify(alarm.details || alarm.data, null, 2)}
                </pre>
              </div>
            )}

            {alarm.status !== 'resolved' && (
              <div className="pt-4 border-t border-slate-700 space-y-3">
                {alarm.status === 'active' && (
                  <button
                    onClick={onAcknowledge}
                    className="w-full px-4 py-2 bg-yellow-600 hover:bg-yellow-500 text-white rounded-lg"
                  >
                    Acknowledge
                  </button>
                )}
                <div className="flex items-center gap-3">
                  <input
                    type="text"
                    value={resolution}
                    onChange={(e) => setResolution(e.target.value)}
                    placeholder="Resolution notes..."
                    className="flex-1 bg-slate-700 text-white px-3 py-2 rounded-lg border border-slate-600 focus:border-stellar-500 outline-none"
                  />
                  <button
                    onClick={() => onResolve(resolution)}
                    className="px-4 py-2 bg-green-600 hover:bg-green-500 text-white rounded-lg"
                  >
                    Resolve
                  </button>
                </div>
              </div>
            )}

            {alarm.status === 'resolved' && (
              <div className="pt-4 border-t border-slate-700">
                <button
                  onClick={onClose}
                  className="px-4 py-2 bg-slate-600 hover:bg-slate-500 text-white rounded-lg"
                >
                  Close
                </button>
              </div>
            )}
          </div>
        </div>
      </div>
    </div>
  )
}
