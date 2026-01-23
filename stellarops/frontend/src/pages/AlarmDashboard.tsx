import { useState, useEffect, useCallback } from 'react'
import type { Alarm, AlarmSeverity, AlarmStatus } from '../types'
import { api, type AlarmFilters } from '../services/api'

type SortField = 'severity' | 'triggered_at' | 'status'

export default function AlarmDashboard() {
  const [alarms, setAlarms] = useState<Alarm[]>([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)
  const [selectedAlarm, setSelectedAlarm] = useState<Alarm | null>(null)

  // Filters
  const [statusFilter, setStatusFilter] = useState<AlarmStatus | 'all'>('all')
  const [severityFilter, setSeverityFilter] = useState<AlarmSeverity | 'all'>('all')
  const [sortField, setSortField] = useState<SortField>('triggered_at')
  const [showAcknowledged, setShowAcknowledged] = useState(true)

  // Fetch alarms
  const fetchAlarms = useCallback(async () => {
    try {
      setLoading(true)
      const filters: AlarmFilters = {}
      if (statusFilter !== 'all') filters.status = statusFilter
      if (severityFilter !== 'all') filters.severity = severityFilter
      const data = await api.alarms.list(filters)
      setAlarms(data)
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to fetch alarms')
    } finally {
      setLoading(false)
    }
  }, [statusFilter, severityFilter])

  useEffect(() => {
    fetchAlarms()
    // Auto-refresh every 10 seconds
    const interval = setInterval(fetchAlarms, 10000)
    return () => clearInterval(interval)
  }, [fetchAlarms])

  // Sort and filter alarms
  const filteredAlarms = alarms.filter((alarm) => {
    if (!showAcknowledged && alarm.acknowledged) return false
    return true
  })

  const sortedAlarms = [...filteredAlarms].sort((a, b) => {
    switch (sortField) {
      case 'severity':
        const severityOrder = { critical: 0, high: 1, medium: 2, low: 3, info: 4 }
        return severityOrder[a.severity] - severityOrder[b.severity]
      case 'triggered_at':
        return new Date(b.triggered_at).getTime() - new Date(a.triggered_at).getTime()
      case 'status':
        const statusOrder = { active: 0, acknowledged: 1, resolved: 2 }
        return statusOrder[a.status] - statusOrder[b.status]
      default:
        return 0
    }
  })

  // Acknowledge handler
  const handleAcknowledge = async (id: string) => {
    try {
      await api.alarms.acknowledge(id)
      fetchAlarms()
    } catch (err) {
      alert(err instanceof Error ? err.message : 'Failed to acknowledge')
    }
  }

  // Resolve handler
  const handleResolve = async (id: string, resolution: string) => {
    try {
      await api.alarms.resolve(id, resolution)
      fetchAlarms()
      if (selectedAlarm?.id === id) setSelectedAlarm(null)
    } catch (err) {
      alert(err instanceof Error ? err.message : 'Failed to resolve')
    }
  }

  // Count by severity
  const alarmCounts = {
    critical: alarms.filter((a) => a.severity === 'critical' && a.status === 'active').length,
    high: alarms.filter((a) => a.severity === 'high' && a.status === 'active').length,
    medium: alarms.filter((a) => a.severity === 'medium' && a.status === 'active').length,
    low: alarms.filter((a) => a.severity === 'low' && a.status === 'active').length,
    info: alarms.filter((a) => a.severity === 'info' && a.status === 'active').length,
  }

  return (
    <div className="h-[calc(100vh-200px)] flex flex-col gap-4">
      {/* Summary Cards */}
      <div className="flex gap-4">
        <SummaryCard label="Critical" count={alarmCounts.critical} color="red" />
        <SummaryCard label="High" count={alarmCounts.high} color="orange" />
        <SummaryCard label="Medium" count={alarmCounts.medium} color="yellow" />
        <SummaryCard label="Low" count={alarmCounts.low} color="blue" />
        <SummaryCard label="Info" count={alarmCounts.info} color="slate" />
      </div>

      <div className="flex-1 flex gap-4">
        {/* Alarm List */}
        <div className="flex-1 bg-slate-800 rounded-lg border border-slate-700 flex flex-col">
          {/* Header */}
          <div className="p-4 border-b border-slate-700">
            <div className="flex items-center justify-between mb-3">
              <h2 className="text-lg font-semibold text-white">
                Active Alarms ({filteredAlarms.length})
              </h2>
              <button
                onClick={fetchAlarms}
                className="text-sm text-stellar-400 hover:text-stellar-300"
              >
                Refresh
              </button>
            </div>

            {/* Filters */}
            <div className="flex gap-2">
              <select
                value={statusFilter}
                onChange={(e) => setStatusFilter(e.target.value as AlarmStatus | 'all')}
                className="bg-slate-700 text-slate-200 rounded px-2 py-1 text-sm border border-slate-600"
              >
                <option value="all">All Status</option>
                <option value="active">Active</option>
                <option value="acknowledged">Acknowledged</option>
                <option value="resolved">Resolved</option>
              </select>
              <select
                value={severityFilter}
                onChange={(e) => setSeverityFilter(e.target.value as AlarmSeverity | 'all')}
                className="bg-slate-700 text-slate-200 rounded px-2 py-1 text-sm border border-slate-600"
              >
                <option value="all">All Severities</option>
                <option value="critical">Critical</option>
                <option value="high">High</option>
                <option value="medium">Medium</option>
                <option value="low">Low</option>
                <option value="info">Info</option>
              </select>
              <select
                value={sortField}
                onChange={(e) => setSortField(e.target.value as SortField)}
                className="bg-slate-700 text-slate-200 rounded px-2 py-1 text-sm border border-slate-600"
              >
                <option value="triggered_at">Sort by Time</option>
                <option value="severity">Sort by Severity</option>
                <option value="status">Sort by Status</option>
              </select>
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
          </div>

          {/* Alarm List */}
          <div className="flex-1 overflow-y-auto">
            {loading ? (
              <div className="p-4 text-center text-slate-400">Loading...</div>
            ) : error ? (
              <div className="p-4 text-center text-red-400">{error}</div>
            ) : sortedAlarms.length === 0 ? (
              <div className="p-4 text-center text-slate-400">No alarms found</div>
            ) : (
              <div className="divide-y divide-slate-700">
                {sortedAlarms.map((alarm) => (
                  <AlarmRow
                    key={alarm.id}
                    alarm={alarm}
                    selected={selectedAlarm?.id === alarm.id}
                    onClick={() => setSelectedAlarm(alarm)}
                    onAcknowledge={() => handleAcknowledge(alarm.id)}
                  />
                ))}
              </div>
            )}
          </div>
        </div>

        {/* Alarm Detail Panel */}
        <div className="w-96 bg-slate-800 rounded-lg border border-slate-700 flex flex-col">
          {selectedAlarm ? (
            <AlarmDetail
              alarm={selectedAlarm}
              onAcknowledge={() => handleAcknowledge(selectedAlarm.id)}
              onResolve={(resolution) => handleResolve(selectedAlarm.id, resolution)}
            />
          ) : (
            <div className="flex-1 flex items-center justify-center text-slate-400">
              Select an alarm to view details
            </div>
          )}
        </div>
      </div>
    </div>
  )
}

// Summary Card
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

// Alarm Row
function AlarmRow({
  alarm,
  selected,
  onClick,
  onAcknowledge,
}: {
  alarm: Alarm
  selected: boolean
  onClick: () => void
  onAcknowledge: () => void
}) {
  return (
    <div
      onClick={onClick}
      className={`p-4 cursor-pointer transition-colors ${
        selected ? 'bg-stellar-600/20' : 'hover:bg-slate-700/50'
      }`}
    >
      <div className="flex items-start gap-3">
        <SeverityIndicator severity={alarm.severity} pulsate={alarm.status === 'active'} />
        <div className="flex-1 min-w-0">
          <div className="flex items-center gap-2">
            <span className="text-white font-medium truncate">{alarm.title}</span>
            {alarm.acknowledged && (
              <span className="text-xs text-slate-500 bg-slate-700 px-1.5 py-0.5 rounded">
                ACK
              </span>
            )}
          </div>
          <p className="text-sm text-slate-400 truncate">{alarm.message}</p>
          <div className="flex items-center gap-4 mt-1 text-xs text-slate-500">
            <span>Satellite: {alarm.satellite_id.slice(0, 8)}...</span>
            <span>{new Date(alarm.triggered_at).toLocaleString()}</span>
          </div>
        </div>
        {alarm.status === 'active' && !alarm.acknowledged && (
          <button
            onClick={(e) => {
              e.stopPropagation()
              onAcknowledge()
            }}
            className="text-xs text-stellar-400 hover:text-stellar-300 px-2 py-1 border border-stellar-500/50 rounded"
          >
            ACK
          </button>
        )}
      </div>
    </div>
  )
}

// Severity Indicator
function SeverityIndicator({
  severity,
  pulsate,
}: {
  severity: AlarmSeverity
  pulsate: boolean
}) {
  const colors = {
    critical: 'bg-red-500',
    high: 'bg-orange-500',
    medium: 'bg-yellow-500',
    low: 'bg-blue-500',
    info: 'bg-slate-500',
  }

  return (
    <div className={`w-3 h-3 rounded-full ${colors[severity]} ${pulsate ? 'animate-pulse' : ''}`} />
  )
}

// Alarm Detail
function AlarmDetail({
  alarm,
  onAcknowledge,
  onResolve,
}: {
  alarm: Alarm
  onAcknowledge: () => void
  onResolve: (resolution: string) => void
}) {
  const [resolution, setResolution] = useState('')

  return (
    <>
      <div className="p-4 border-b border-slate-700">
        <div className="flex items-center gap-2 mb-2">
          <SeverityIndicator severity={alarm.severity} pulsate={alarm.status === 'active'} />
          <span
            className={`text-xs px-2 py-0.5 rounded uppercase font-medium ${
              {
                critical: 'text-red-400 bg-red-400/10',
                high: 'text-orange-400 bg-orange-400/10',
                medium: 'text-yellow-400 bg-yellow-400/10',
                low: 'text-blue-400 bg-blue-400/10',
                info: 'text-slate-400 bg-slate-400/10',
              }[alarm.severity]
            }`}
          >
            {alarm.severity}
          </span>
          <span
            className={`text-xs px-2 py-0.5 rounded uppercase font-medium ${
              {
                active: 'text-red-400 bg-red-400/10',
                acknowledged: 'text-yellow-400 bg-yellow-400/10',
                resolved: 'text-green-400 bg-green-400/10',
              }[alarm.status]
            }`}
          >
            {alarm.status}
          </span>
        </div>
        <h3 className="text-lg font-semibold text-white">{alarm.title}</h3>
      </div>

      <div className="flex-1 overflow-y-auto p-4 space-y-4">
        {/* Message */}
        <div>
          <h4 className="text-xs text-slate-400 uppercase mb-1">Message</h4>
          <p className="text-slate-200">{alarm.message}</p>
        </div>

        {/* Timing */}
        <div className="bg-slate-700/50 rounded p-3 space-y-2 text-sm">
          <div className="flex justify-between">
            <span className="text-slate-400">Triggered:</span>
            <span className="text-slate-200">
              {new Date(alarm.triggered_at).toLocaleString()}
            </span>
          </div>
          {alarm.acknowledged_at && (
            <div className="flex justify-between">
              <span className="text-slate-400">Acknowledged:</span>
              <span className="text-slate-200">
                {new Date(alarm.acknowledged_at).toLocaleString()}
              </span>
            </div>
          )}
          {alarm.acknowledged_by && (
            <div className="flex justify-between">
              <span className="text-slate-400">Acknowledged by:</span>
              <span className="text-slate-200">{alarm.acknowledged_by}</span>
            </div>
          )}
          {alarm.resolved_at && (
            <div className="flex justify-between">
              <span className="text-slate-400">Resolved:</span>
              <span className="text-slate-200">
                {new Date(alarm.resolved_at).toLocaleString()}
              </span>
            </div>
          )}
        </div>

        {/* Resolution */}
        {alarm.resolution && (
          <div className="bg-green-500/10 border border-green-500/50 rounded p-3">
            <h4 className="text-xs text-green-400 uppercase mb-1">Resolution</h4>
            <p className="text-sm text-slate-200">{alarm.resolution}</p>
          </div>
        )}

        {/* Data */}
        {alarm.data && Object.keys(alarm.data).length > 0 && (
          <div className="bg-slate-700/50 rounded p-3">
            <h4 className="text-xs text-slate-400 uppercase mb-2">Additional Data</h4>
            <pre className="text-xs text-slate-300 overflow-x-auto">
              {JSON.stringify(alarm.data, null, 2)}
            </pre>
          </div>
        )}
      </div>

      {/* Actions */}
      {alarm.status !== 'resolved' && (
        <div className="p-4 border-t border-slate-700 space-y-3">
          {!alarm.acknowledged && (
            <button
              onClick={onAcknowledge}
              className="w-full px-4 py-2 bg-stellar-600 hover:bg-stellar-500 text-white rounded transition-colors"
            >
              Acknowledge
            </button>
          )}
          <div className="flex gap-2">
            <input
              type="text"
              value={resolution}
              onChange={(e) => setResolution(e.target.value)}
              placeholder="Resolution notes..."
              className="flex-1 bg-slate-700 text-slate-200 rounded px-3 py-2 text-sm border border-slate-600 focus:border-stellar-500 outline-none"
            />
            <button
              onClick={() => {
                if (resolution.trim()) {
                  onResolve(resolution)
                  setResolution('')
                }
              }}
              disabled={!resolution.trim()}
              className="px-4 py-2 bg-green-600 hover:bg-green-500 disabled:bg-slate-600 disabled:text-slate-400 text-white rounded transition-colors"
            >
              Resolve
            </button>
          </div>
        </div>
      )}
    </>
  )
}
