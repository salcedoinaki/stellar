import { useState, useEffect, useCallback } from 'react'
import type { Mission, MissionStatus, MissionPriority } from '../types'
import { api, type MissionFilters } from '../services/api'

type SortField = 'priority' | 'deadline' | 'status' | 'inserted_at'

export default function MissionDashboard() {
  const [missions, setMissions] = useState<Mission[]>([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)
  const [selectedMission, setSelectedMission] = useState<Mission | null>(null)

  // Filters
  const [statusFilter, setStatusFilter] = useState<MissionStatus | 'all'>('all')
  const [priorityFilter, setPriorityFilter] = useState<MissionPriority | 'all'>('all')
  const [sortField, setSortField] = useState<SortField>('priority')

  // Fetch missions
  const fetchMissions = useCallback(async () => {
    try {
      setLoading(true)
      const filters: MissionFilters = {}
      if (statusFilter !== 'all') filters.status = statusFilter
      if (priorityFilter !== 'all') filters.priority = priorityFilter
      const data = await api.missions.list(filters)
      setMissions(data)
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to fetch missions')
    } finally {
      setLoading(false)
    }
  }, [statusFilter, priorityFilter])

  useEffect(() => {
    fetchMissions()
  }, [fetchMissions])

  // Sort missions
  const sortedMissions = [...missions].sort((a, b) => {
    switch (sortField) {
      case 'priority':
        const priorityOrder = { critical: 0, high: 1, normal: 2, low: 3 }
        return priorityOrder[a.priority] - priorityOrder[b.priority]
      case 'deadline':
        if (!a.deadline) return 1
        if (!b.deadline) return -1
        return new Date(a.deadline).getTime() - new Date(b.deadline).getTime()
      case 'status':
        const statusOrder = { running: 0, scheduled: 1, pending: 2, completed: 3, failed: 4, canceled: 5 }
        return statusOrder[a.status] - statusOrder[b.status]
      case 'inserted_at':
        return new Date(b.inserted_at).getTime() - new Date(a.inserted_at).getTime()
      default:
        return 0
    }
  })

  // Cancel mission handler
  const handleCancel = async (id: string) => {
    if (!confirm('Are you sure you want to cancel this mission?')) return
    try {
      await api.missions.cancel(id)
      fetchMissions()
      if (selectedMission?.id === id) setSelectedMission(null)
    } catch (err) {
      alert(err instanceof Error ? err.message : 'Failed to cancel mission')
    }
  }

  return (
    <div className="h-[calc(100vh-200px)] flex gap-4">
      {/* Mission List */}
      <div className="flex-1 bg-slate-800 rounded-lg border border-slate-700 flex flex-col">
        {/* Header */}
        <div className="p-4 border-b border-slate-700">
          <div className="flex items-center justify-between mb-3">
            <h2 className="text-lg font-semibold text-white">Missions</h2>
            <button
              onClick={fetchMissions}
              className="text-sm text-stellar-400 hover:text-stellar-300"
            >
              Refresh
            </button>
          </div>

          {/* Filters */}
          <div className="flex gap-2">
            <select
              value={statusFilter}
              onChange={(e) => setStatusFilter(e.target.value as MissionStatus | 'all')}
              className="bg-slate-700 text-slate-200 rounded px-2 py-1 text-sm border border-slate-600"
            >
              <option value="all">All Status</option>
              <option value="pending">Pending</option>
              <option value="scheduled">Scheduled</option>
              <option value="running">Running</option>
              <option value="completed">Completed</option>
              <option value="failed">Failed</option>
              <option value="canceled">Canceled</option>
            </select>
            <select
              value={priorityFilter}
              onChange={(e) => setPriorityFilter(e.target.value as MissionPriority | 'all')}
              className="bg-slate-700 text-slate-200 rounded px-2 py-1 text-sm border border-slate-600"
            >
              <option value="all">All Priorities</option>
              <option value="critical">Critical</option>
              <option value="high">High</option>
              <option value="normal">Normal</option>
              <option value="low">Low</option>
            </select>
            <select
              value={sortField}
              onChange={(e) => setSortField(e.target.value as SortField)}
              className="bg-slate-700 text-slate-200 rounded px-2 py-1 text-sm border border-slate-600"
            >
              <option value="priority">Sort by Priority</option>
              <option value="deadline">Sort by Deadline</option>
              <option value="status">Sort by Status</option>
              <option value="inserted_at">Sort by Created</option>
            </select>
          </div>
        </div>

        {/* Mission List */}
        <div className="flex-1 overflow-y-auto">
          {loading ? (
            <div className="p-4 text-center text-slate-400">Loading...</div>
          ) : error ? (
            <div className="p-4 text-center text-red-400">{error}</div>
          ) : sortedMissions.length === 0 ? (
            <div className="p-4 text-center text-slate-400">No missions found</div>
          ) : (
            <table className="w-full">
              <thead className="bg-slate-700/50 sticky top-0">
                <tr className="text-left text-xs text-slate-400">
                  <th className="p-3">Name</th>
                  <th className="p-3">Type</th>
                  <th className="p-3">Priority</th>
                  <th className="p-3">Status</th>
                  <th className="p-3">Satellite</th>
                  <th className="p-3">Deadline</th>
                  <th className="p-3">Actions</th>
                </tr>
              </thead>
              <tbody>
                {sortedMissions.map((mission) => (
                  <tr
                    key={mission.id}
                    onClick={() => setSelectedMission(mission)}
                    className={`border-b border-slate-700 cursor-pointer transition-colors ${
                      selectedMission?.id === mission.id
                        ? 'bg-stellar-600/20'
                        : 'hover:bg-slate-700/50'
                    }`}
                  >
                    <td className="p-3">
                      <div className="text-white font-medium">{mission.name}</div>
                      <div className="text-xs text-slate-400 truncate max-w-[200px]">
                        {mission.description}
                      </div>
                    </td>
                    <td className="p-3 text-sm text-slate-300">{mission.type}</td>
                    <td className="p-3">
                      <PriorityBadge priority={mission.priority} />
                    </td>
                    <td className="p-3">
                      <StatusBadge status={mission.status} />
                    </td>
                    <td className="p-3 text-sm text-slate-300 font-mono">
                      {mission.satellite_id.slice(0, 8)}...
                    </td>
                    <td className="p-3 text-sm text-slate-300">
                      {mission.deadline
                        ? new Date(mission.deadline).toLocaleString()
                        : '—'}
                    </td>
                    <td className="p-3">
                      {['pending', 'scheduled'].includes(mission.status) && (
                        <button
                          onClick={(e) => {
                            e.stopPropagation()
                            handleCancel(mission.id)
                          }}
                          className="text-xs text-red-400 hover:text-red-300"
                        >
                          Cancel
                        </button>
                      )}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          )}
        </div>
      </div>

      {/* Mission Detail Panel */}
      <div className="w-96 bg-slate-800 rounded-lg border border-slate-700 flex flex-col">
        {selectedMission ? (
          <>
            <div className="p-4 border-b border-slate-700">
              <h3 className="text-lg font-semibold text-white">{selectedMission.name}</h3>
              <p className="text-sm text-slate-400 mt-1">{selectedMission.description}</p>
            </div>
            <div className="flex-1 overflow-y-auto p-4 space-y-4">
              {/* Status */}
              <div className="flex items-center justify-between">
                <span className="text-slate-400">Status:</span>
                <StatusBadge status={selectedMission.status} />
              </div>
              <div className="flex items-center justify-between">
                <span className="text-slate-400">Priority:</span>
                <PriorityBadge priority={selectedMission.priority} />
              </div>

              {/* Timing */}
              <div className="bg-slate-700/50 rounded p-3 space-y-2 text-sm">
                <h4 className="text-xs text-slate-400 uppercase mb-2">Timing</h4>
                {selectedMission.deadline && (
                  <div className="flex justify-between">
                    <span className="text-slate-400">Deadline:</span>
                    <span className="text-slate-200">
                      {new Date(selectedMission.deadline).toLocaleString()}
                    </span>
                  </div>
                )}
                {selectedMission.scheduled_at && (
                  <div className="flex justify-between">
                    <span className="text-slate-400">Scheduled:</span>
                    <span className="text-slate-200">
                      {new Date(selectedMission.scheduled_at).toLocaleString()}
                    </span>
                  </div>
                )}
                {selectedMission.started_at && (
                  <div className="flex justify-between">
                    <span className="text-slate-400">Started:</span>
                    <span className="text-slate-200">
                      {new Date(selectedMission.started_at).toLocaleString()}
                    </span>
                  </div>
                )}
                {selectedMission.completed_at && (
                  <div className="flex justify-between">
                    <span className="text-slate-400">Completed:</span>
                    <span className="text-slate-200">
                      {new Date(selectedMission.completed_at).toLocaleString()}
                    </span>
                  </div>
                )}
              </div>

              {/* Resources */}
              <div className="bg-slate-700/50 rounded p-3 space-y-2 text-sm">
                <h4 className="text-xs text-slate-400 uppercase mb-2">Resource Requirements</h4>
                <div className="flex justify-between">
                  <span className="text-slate-400">Energy:</span>
                  <span className="text-slate-200">{selectedMission.required_energy}%</span>
                </div>
                <div className="flex justify-between">
                  <span className="text-slate-400">Memory:</span>
                  <span className="text-slate-200">{selectedMission.required_memory}%</span>
                </div>
                <div className="flex justify-between">
                  <span className="text-slate-400">Bandwidth:</span>
                  <span className="text-slate-200">{selectedMission.required_bandwidth} Mbps</span>
                </div>
                <div className="flex justify-between">
                  <span className="text-slate-400">Est. Duration:</span>
                  <span className="text-slate-200">{selectedMission.estimated_duration}s</span>
                </div>
              </div>

              {/* Retry Info */}
              {selectedMission.retry_count > 0 && (
                <div className="bg-yellow-500/10 border border-yellow-500/50 rounded p-3">
                  <h4 className="text-xs text-yellow-400 uppercase mb-2">Retry History</h4>
                  <div className="text-sm">
                    <span className="text-yellow-400">Retries:</span>
                    <span className="ml-2 text-white">
                      {selectedMission.retry_count} / {selectedMission.max_retries}
                    </span>
                  </div>
                  {selectedMission.last_error && (
                    <div className="text-xs text-red-400 mt-2">
                      Last Error: {selectedMission.last_error}
                    </div>
                  )}
                </div>
              )}

              {/* Payload */}
              {selectedMission.payload && Object.keys(selectedMission.payload).length > 0 && (
                <div className="bg-slate-700/50 rounded p-3">
                  <h4 className="text-xs text-slate-400 uppercase mb-2">Payload</h4>
                  <pre className="text-xs text-slate-300 overflow-x-auto">
                    {JSON.stringify(selectedMission.payload, null, 2)}
                  </pre>
                </div>
              )}

              {/* Result */}
              {selectedMission.result && Object.keys(selectedMission.result).length > 0 && (
                <div className="bg-green-500/10 border border-green-500/50 rounded p-3">
                  <h4 className="text-xs text-green-400 uppercase mb-2">Result</h4>
                  <pre className="text-xs text-slate-300 overflow-x-auto">
                    {JSON.stringify(selectedMission.result, null, 2)}
                  </pre>
                </div>
              )}
            </div>
          </>
        ) : (
          <div className="flex-1 flex items-center justify-center text-slate-400">
            Select a mission to view details
          </div>
        )}
      </div>
    </div>
  )
}

// Priority Badge
function PriorityBadge({ priority }: { priority: MissionPriority }) {
  const colors = {
    critical: 'text-red-400 bg-red-400/10',
    high: 'text-orange-400 bg-orange-400/10',
    normal: 'text-blue-400 bg-blue-400/10',
    low: 'text-slate-400 bg-slate-400/10',
  }

  return (
    <span className={`px-2 py-0.5 rounded text-xs font-medium uppercase ${colors[priority]}`}>
      {priority}
    </span>
  )
}

// Status Badge
function StatusBadge({ status }: { status: MissionStatus }) {
  const colors = {
    pending: 'text-yellow-400 bg-yellow-400/10',
    scheduled: 'text-blue-400 bg-blue-400/10',
    running: 'text-cyan-400 bg-cyan-400/10 animate-pulse',
    completed: 'text-green-400 bg-green-400/10',
    failed: 'text-red-400 bg-red-400/10',
    canceled: 'text-slate-400 bg-slate-400/10',
  }

  return (
    <span className={`px-2 py-0.5 rounded text-xs font-medium uppercase ${colors[status]}`}>
      {status}
    </span>
  )
}
