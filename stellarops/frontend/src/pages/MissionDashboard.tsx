import { useEffect, useState, useCallback } from 'react'
import { useSatelliteStore } from '../store/satelliteStore'
import { api } from '../services/api'
import type { Mission, MissionStatus, MissionPriority } from '../types'

type SortField = 'priority' | 'deadline' | 'status' | 'satellite_id'
type SortOrder = 'asc' | 'desc'

interface MissionFilters {
  status?: MissionStatus
  priority?: MissionPriority
  satellite_id?: string
}

export function MissionDashboard() {
  const { satellites, isConnected } = useSatelliteStore()
  
  const [missions, setMissions] = useState<Mission[]>([])
  const [selectedMission, setSelectedMission] = useState<Mission | null>(null)
  const [isLoading, setIsLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)
  const [filters, setFilters] = useState<MissionFilters>({})
  const [sortField, setSortField] = useState<SortField>('priority')
  const [sortOrder, setSortOrder] = useState<SortOrder>('asc')
  const [showCreateModal, setShowCreateModal] = useState(false)
  const [showDetailModal, setShowDetailModal] = useState(false)
  
  // Stats
  const pendingCount = missions.filter(m => m.status === 'pending').length
  const runningCount = missions.filter(m => m.status === 'running').length
  const completedCount = missions.filter(m => m.status === 'completed').length
  const failedCount = missions.filter(m => m.status === 'failed').length

  // Fetch missions
  const fetchMissions = useCallback(async () => {
    try {
      setIsLoading(true)
      const data = await api.getMissions(filters)
      setMissions(data)
      setError(null)
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to fetch missions')
    } finally {
      setIsLoading(false)
    }
  }, [filters])

  useEffect(() => {
    fetchMissions()
    // Refresh every 15 seconds
    const interval = setInterval(fetchMissions, 15000)
    return () => clearInterval(interval)
  }, [fetchMissions])

  // Sort missions
  const priorityOrder: Record<MissionPriority, number> = { 
    critical: 0, 
    high: 1, 
    normal: 2, 
    low: 3 
  }

  const statusOrder: Record<MissionStatus, number> = {
    running: 0,
    pending: 1,
    completed: 2,
    failed: 3,
    cancelled: 4
  }

  const sortedMissions = [...missions].sort((a, b) => {
    let comparison = 0
    switch (sortField) {
      case 'priority':
        comparison = (priorityOrder[a.priority] || 5) - (priorityOrder[b.priority] || 5)
        break
      case 'deadline':
        comparison = new Date(a.deadline || 0).getTime() - new Date(b.deadline || 0).getTime()
        break
      case 'status':
        comparison = (statusOrder[a.status] || 5) - (statusOrder[b.status] || 5)
        break
      case 'satellite_id':
        comparison = (a.satellite_id || '').localeCompare(b.satellite_id || '')
        break
    }
    return sortOrder === 'asc' ? comparison : -comparison
  })

  // Cancel mission
  const handleCancel = async (missionId: string) => {
    if (!confirm('Are you sure you want to cancel this mission?')) return
    
    try {
      await api.cancelMission(missionId)
      fetchMissions()
    } catch (err) {
      console.error('Failed to cancel mission:', err)
    }
  }

  // Retry mission
  const handleRetry = async (missionId: string) => {
    try {
      await api.retryMission(missionId)
      fetchMissions()
    } catch (err) {
      console.error('Failed to retry mission:', err)
    }
  }

  const getPriorityColor = (priority: MissionPriority) => {
    switch (priority) {
      case 'critical': return 'bg-red-500/20 text-red-400 border-red-500/50'
      case 'high': return 'bg-orange-500/20 text-orange-400 border-orange-500/50'
      case 'normal': return 'bg-blue-500/20 text-blue-400 border-blue-500/50'
      case 'low': return 'bg-slate-500/20 text-slate-400 border-slate-500/50'
      default: return 'bg-slate-500/20 text-slate-400 border-slate-500/50'
    }
  }

  const getStatusColor = (status: MissionStatus) => {
    switch (status) {
      case 'running': return 'bg-green-500/20 text-green-400'
      case 'pending': return 'bg-yellow-500/20 text-yellow-400'
      case 'completed': return 'bg-blue-500/20 text-blue-400'
      case 'failed': return 'bg-red-500/20 text-red-400'
      case 'cancelled': return 'bg-slate-500/20 text-slate-400'
      default: return 'bg-slate-500/20 text-slate-400'
    }
  }

  const getStatusIcon = (status: MissionStatus) => {
    switch (status) {
      case 'running': return '▶️'
      case 'pending': return '⏳'
      case 'completed': return '✅'
      case 'failed': return '❌'
      case 'cancelled': return '🚫'
      default: return '❓'
    }
  }

  const formatTime = (dateStr: string | null) => {
    if (!dateStr) return 'N/A'
    const date = new Date(dateStr)
    return date.toLocaleString()
  }

  const formatDuration = (startTime: string | null, endTime: string | null) => {
    if (!startTime) return 'N/A'
    const start = new Date(startTime)
    const end = endTime ? new Date(endTime) : new Date()
    const diffMs = end.getTime() - start.getTime()
    const diffSecs = Math.floor(diffMs / 1000)
    const mins = Math.floor(diffSecs / 60)
    const secs = diffSecs % 60
    return `${mins}m ${secs}s`
  }

  const getSatelliteName = (id: string | null) => {
    if (!id) return 'Unassigned'
    const sat = satellites.get(id)
    return sat?.name || id.slice(0, 8)
  }

  return (
    <div className="space-y-6">
      {/* Header */}
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-bold text-white">Mission Dashboard</h1>
          <p className="text-slate-400 text-sm mt-1">
            Manage satellite missions and tasks
          </p>
        </div>
        <div className="flex items-center gap-3">
          <button
            onClick={() => setShowCreateModal(true)}
            className="px-4 py-2 bg-stellar-600 hover:bg-stellar-500 text-white text-sm rounded-lg transition-colors flex items-center gap-2"
          >
            <span>➕</span>
            New Mission
          </button>
          <button
            onClick={fetchMissions}
            disabled={isLoading}
            className="px-4 py-2 bg-slate-700 hover:bg-slate-600 text-white text-sm rounded-lg transition-colors flex items-center gap-2"
          >
            <span className={isLoading ? 'animate-spin' : ''}>🔄</span>
            Refresh
          </button>
        </div>
      </div>

      {/* Stats Row */}
      <div className="grid grid-cols-4 gap-4">
        <div className="bg-yellow-500/10 border border-yellow-500/30 rounded-lg p-4">
          <div className="text-yellow-400 text-sm">Pending</div>
          <div className="text-2xl font-bold text-yellow-400">{pendingCount}</div>
        </div>
        <div className="bg-green-500/10 border border-green-500/30 rounded-lg p-4">
          <div className="text-green-400 text-sm">Running</div>
          <div className="text-2xl font-bold text-green-400">{runningCount}</div>
        </div>
        <div className="bg-blue-500/10 border border-blue-500/30 rounded-lg p-4">
          <div className="text-blue-400 text-sm">Completed</div>
          <div className="text-2xl font-bold text-blue-400">{completedCount}</div>
        </div>
        <div className="bg-red-500/10 border border-red-500/30 rounded-lg p-4">
          <div className="text-red-400 text-sm">Failed</div>
          <div className="text-2xl font-bold text-red-400">{failedCount}</div>
        </div>
      </div>

      {/* Filters Bar */}
      <div className="bg-slate-800 rounded-lg p-4 flex items-center gap-4 flex-wrap">
        {/* Status Filter */}
        <select
          value={filters.status || ''}
          onChange={(e) => setFilters({ ...filters, status: e.target.value as MissionStatus || undefined })}
          className="bg-slate-700 border border-slate-600 text-white text-sm rounded-lg px-3 py-2"
        >
          <option value="">All Statuses</option>
          <option value="pending">Pending</option>
          <option value="running">Running</option>
          <option value="completed">Completed</option>
          <option value="failed">Failed</option>
          <option value="cancelled">Cancelled</option>
        </select>

        {/* Priority Filter */}
        <select
          value={filters.priority || ''}
          onChange={(e) => setFilters({ ...filters, priority: e.target.value as MissionPriority || undefined })}
          className="bg-slate-700 border border-slate-600 text-white text-sm rounded-lg px-3 py-2"
        >
          <option value="">All Priorities</option>
          <option value="critical">Critical</option>
          <option value="high">High</option>
          <option value="normal">Normal</option>
          <option value="low">Low</option>
        </select>

        {/* Satellite Filter */}
        <select
          value={filters.satellite_id || ''}
          onChange={(e) => setFilters({ ...filters, satellite_id: e.target.value || undefined })}
          className="bg-slate-700 border border-slate-600 text-white text-sm rounded-lg px-3 py-2"
        >
          <option value="">All Satellites</option>
          {[...satellites.values()].map((sat) => (
            <option key={sat.id} value={sat.id}>{sat.name}</option>
          ))}
        </select>

        {/* Sort */}
        <div className="flex items-center gap-2">
          <select
            value={sortField}
            onChange={(e) => setSortField(e.target.value as SortField)}
            className="bg-slate-700 border border-slate-600 text-white text-sm rounded-lg px-3 py-2"
          >
            <option value="priority">Sort by Priority</option>
            <option value="deadline">Sort by Deadline</option>
            <option value="status">Sort by Status</option>
            <option value="satellite_id">Sort by Satellite</option>
          </select>

          <button
            onClick={() => setSortOrder(sortOrder === 'asc' ? 'desc' : 'asc')}
            className="p-2 bg-slate-700 hover:bg-slate-600 text-white rounded-lg"
          >
            {sortOrder === 'asc' ? '↑' : '↓'}
          </button>
        </div>
      </div>

      {/* Error Display */}
      {error && (
        <div className="bg-red-500/20 border border-red-500/50 text-red-400 px-4 py-3 rounded-lg">
          {error}
        </div>
      )}

      {/* Mission Grid */}
      {isLoading && missions.length === 0 ? (
        <div className="p-8 text-center text-slate-400">
          Loading missions...
        </div>
      ) : sortedMissions.length === 0 ? (
        <div className="p-8 text-center text-slate-400 bg-slate-800 rounded-lg">
          No missions found
        </div>
      ) : (
        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
          {sortedMissions.map((mission) => (
            <div
              key={mission.id}
              className={`bg-slate-800 border border-slate-700 rounded-lg p-4 hover:border-stellar-500/50 transition-colors cursor-pointer ${
                selectedMission?.id === mission.id ? 'border-stellar-500' : ''
              }`}
              onClick={() => {
                setSelectedMission(mission)
                setShowDetailModal(true)
              }}
            >
              {/* Header */}
              <div className="flex items-start justify-between mb-3">
                <div>
                  <h3 className="text-white font-medium">{mission.name || `Mission ${mission.id.slice(0, 8)}`}</h3>
                  <p className="text-slate-400 text-xs">{mission.type}</p>
                </div>
                <span className={`px-2 py-0.5 text-xs rounded border ${getPriorityColor(mission.priority)}`}>
                  {mission.priority}
                </span>
              </div>

              {/* Status */}
              <div className="flex items-center gap-2 mb-3">
                <span className={`px-2 py-1 text-xs rounded ${getStatusColor(mission.status)}`}>
                  {getStatusIcon(mission.status)} {mission.status}
                </span>
                {mission.status === 'running' && (
                  <span className="text-xs text-slate-400">
                    {formatDuration(mission.started_at, null)}
                  </span>
                )}
              </div>

              {/* Details */}
              <div className="space-y-2 text-sm">
                <div className="flex items-center justify-between">
                  <span className="text-slate-400">Satellite</span>
                  <span className="text-white">{getSatelliteName(mission.satellite_id)}</span>
                </div>
                {mission.deadline && (
                  <div className="flex items-center justify-between">
                    <span className="text-slate-400">Deadline</span>
                    <span className="text-white">{formatTime(mission.deadline)}</span>
                  </div>
                )}
                {mission.retry_count > 0 && (
                  <div className="flex items-center justify-between">
                    <span className="text-slate-400">Retries</span>
                    <span className="text-white">{mission.retry_count}/{mission.max_retries}</span>
                  </div>
                )}
              </div>

              {/* Actions */}
              <div className="flex items-center gap-2 mt-4 pt-3 border-t border-slate-700" onClick={(e) => e.stopPropagation()}>
                {(mission.status === 'pending' || mission.status === 'running') && (
                  <button
                    onClick={() => handleCancel(mission.id)}
                    className="px-3 py-1 bg-red-600 hover:bg-red-500 text-white text-xs rounded"
                  >
                    Cancel
                  </button>
                )}
                {mission.status === 'failed' && mission.retry_count < mission.max_retries && (
                  <button
                    onClick={() => handleRetry(mission.id)}
                    className="px-3 py-1 bg-yellow-600 hover:bg-yellow-500 text-white text-xs rounded"
                  >
                    Retry
                  </button>
                )}
              </div>
            </div>
          ))}
        </div>
      )}

      {/* Create Mission Modal */}
      {showCreateModal && (
        <CreateMissionModal
          satellites={[...satellites.values()]}
          onClose={() => setShowCreateModal(false)}
          onCreate={() => {
            setShowCreateModal(false)
            fetchMissions()
          }}
        />
      )}

      {/* Mission Detail Modal */}
      {showDetailModal && selectedMission && (
        <MissionDetailModal
          mission={selectedMission}
          satelliteName={getSatelliteName(selectedMission.satellite_id)}
          onClose={() => setShowDetailModal(false)}
          onCancel={() => {
            handleCancel(selectedMission.id)
            setShowDetailModal(false)
          }}
          onRetry={() => {
            handleRetry(selectedMission.id)
            setShowDetailModal(false)
          }}
        />
      )}
    </div>
  )
}

// Create Mission Modal Component
interface CreateMissionModalProps {
  satellites: Array<{ id: string; name: string }>
  onClose: () => void
  onCreate: () => void
}

function CreateMissionModal({ satellites, onClose, onCreate }: CreateMissionModalProps) {
  const [formData, setFormData] = useState({
    name: '',
    type: 'telemetry',
    satellite_id: '',
    priority: 'normal' as MissionPriority,
    deadline: '',
    payload: '{}'
  })
  const [isSubmitting, setIsSubmitting] = useState(false)
  const [error, setError] = useState<string | null>(null)

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault()
    setIsSubmitting(true)
    setError(null)

    try {
      let payload = {}
      try {
        payload = JSON.parse(formData.payload)
      } catch {
        throw new Error('Invalid payload JSON')
      }

      await api.createMission({
        name: formData.name,
        type: formData.type,
        satellite_id: formData.satellite_id || undefined,
        priority: formData.priority,
        deadline: formData.deadline || undefined,
        payload
      })
      onCreate()
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to create mission')
    } finally {
      setIsSubmitting(false)
    }
  }

  return (
    <div className="fixed inset-0 bg-black/50 flex items-center justify-center z-50 p-4">
      <div className="bg-slate-800 rounded-lg max-w-lg w-full">
        <div className="p-6">
          <div className="flex items-center justify-between mb-4">
            <h2 className="text-xl font-bold text-white">Create New Mission</h2>
            <button onClick={onClose} className="text-slate-400 hover:text-white text-xl">×</button>
          </div>

          {error && (
            <div className="mb-4 bg-red-500/20 border border-red-500/50 text-red-400 px-4 py-2 rounded">
              {error}
            </div>
          )}

          <form onSubmit={handleSubmit} className="space-y-4">
            <div>
              <label className="block text-slate-400 text-sm mb-1">Mission Name</label>
              <input
                type="text"
                value={formData.name}
                onChange={(e) => setFormData({ ...formData, name: e.target.value })}
                className="w-full bg-slate-700 border border-slate-600 text-white rounded-lg px-3 py-2"
                required
              />
            </div>

            <div className="grid grid-cols-2 gap-4">
              <div>
                <label className="block text-slate-400 text-sm mb-1">Type</label>
                <select
                  value={formData.type}
                  onChange={(e) => setFormData({ ...formData, type: e.target.value })}
                  className="w-full bg-slate-700 border border-slate-600 text-white rounded-lg px-3 py-2"
                >
                  <option value="telemetry">Telemetry</option>
                  <option value="imaging">Imaging</option>
                  <option value="communication">Communication</option>
                  <option value="maneuver">Maneuver</option>
                  <option value="maintenance">Maintenance</option>
                </select>
              </div>
              <div>
                <label className="block text-slate-400 text-sm mb-1">Priority</label>
                <select
                  value={formData.priority}
                  onChange={(e) => setFormData({ ...formData, priority: e.target.value as MissionPriority })}
                  className="w-full bg-slate-700 border border-slate-600 text-white rounded-lg px-3 py-2"
                >
                  <option value="low">Low</option>
                  <option value="normal">Normal</option>
                  <option value="high">High</option>
                  <option value="critical">Critical</option>
                </select>
              </div>
            </div>

            <div>
              <label className="block text-slate-400 text-sm mb-1">Satellite</label>
              <select
                value={formData.satellite_id}
                onChange={(e) => setFormData({ ...formData, satellite_id: e.target.value })}
                className="w-full bg-slate-700 border border-slate-600 text-white rounded-lg px-3 py-2"
              >
                <option value="">Select satellite...</option>
                {satellites.map((sat) => (
                  <option key={sat.id} value={sat.id}>{sat.name}</option>
                ))}
              </select>
            </div>

            <div>
              <label className="block text-slate-400 text-sm mb-1">Deadline (optional)</label>
              <input
                type="datetime-local"
                value={formData.deadline}
                onChange={(e) => setFormData({ ...formData, deadline: e.target.value })}
                className="w-full bg-slate-700 border border-slate-600 text-white rounded-lg px-3 py-2"
              />
            </div>

            <div>
              <label className="block text-slate-400 text-sm mb-1">Payload (JSON)</label>
              <textarea
                value={formData.payload}
                onChange={(e) => setFormData({ ...formData, payload: e.target.value })}
                className="w-full bg-slate-700 border border-slate-600 text-white rounded-lg px-3 py-2 font-mono text-sm"
                rows={3}
              />
            </div>

            <div className="flex items-center gap-3 pt-4">
              <button
                type="submit"
                disabled={isSubmitting}
                className="px-4 py-2 bg-stellar-600 hover:bg-stellar-500 text-white rounded-lg disabled:opacity-50"
              >
                {isSubmitting ? 'Creating...' : 'Create Mission'}
              </button>
              <button
                type="button"
                onClick={onClose}
                className="px-4 py-2 bg-slate-600 hover:bg-slate-500 text-white rounded-lg"
              >
                Cancel
              </button>
            </div>
          </form>
        </div>
      </div>
    </div>
  )
}

// Mission Detail Modal Component
interface MissionDetailModalProps {
  mission: Mission
  satelliteName: string
  onClose: () => void
  onCancel: () => void
  onRetry: () => void
}

function MissionDetailModal({ mission, satelliteName, onClose, onCancel, onRetry }: MissionDetailModalProps) {
  const formatTime = (dateStr: string | null) => {
    if (!dateStr) return 'N/A'
    return new Date(dateStr).toLocaleString()
  }

  return (
    <div className="fixed inset-0 bg-black/50 flex items-center justify-center z-50 p-4">
      <div className="bg-slate-800 rounded-lg max-w-2xl w-full max-h-[80vh] overflow-auto">
        <div className="p-6">
          <div className="flex items-start justify-between mb-4">
            <div>
              <h2 className="text-xl font-bold text-white">{mission.name || 'Mission Details'}</h2>
              <p className="text-slate-400 text-sm">ID: {mission.id}</p>
            </div>
            <button onClick={onClose} className="text-slate-400 hover:text-white text-xl">×</button>
          </div>

          <div className="space-y-4">
            <div className="grid grid-cols-2 gap-4">
              <div>
                <label className="text-slate-400 text-sm">Type</label>
                <p className="mt-1 text-white">{mission.type}</p>
              </div>
              <div>
                <label className="text-slate-400 text-sm">Status</label>
                <p className="mt-1 text-white capitalize">{mission.status}</p>
              </div>
              <div>
                <label className="text-slate-400 text-sm">Priority</label>
                <p className="mt-1 text-white capitalize">{mission.priority}</p>
              </div>
              <div>
                <label className="text-slate-400 text-sm">Satellite</label>
                <p className="mt-1 text-white">{satelliteName}</p>
              </div>
            </div>

            <div className="grid grid-cols-3 gap-4">
              <div>
                <label className="text-slate-400 text-sm">Created</label>
                <p className="mt-1 text-white text-sm">{formatTime(mission.inserted_at)}</p>
              </div>
              <div>
                <label className="text-slate-400 text-sm">Started</label>
                <p className="mt-1 text-white text-sm">{formatTime(mission.started_at)}</p>
              </div>
              <div>
                <label className="text-slate-400 text-sm">Completed</label>
                <p className="mt-1 text-white text-sm">{formatTime(mission.completed_at)}</p>
              </div>
            </div>

            {mission.deadline && (
              <div>
                <label className="text-slate-400 text-sm">Deadline</label>
                <p className="mt-1 text-white">{formatTime(mission.deadline)}</p>
              </div>
            )}

            <div className="grid grid-cols-3 gap-4">
              <div>
                <label className="text-slate-400 text-sm">Energy Required</label>
                <p className="mt-1 text-white">{mission.energy_required || 0}%</p>
              </div>
              <div>
                <label className="text-slate-400 text-sm">Memory Required</label>
                <p className="mt-1 text-white">{mission.memory_required || 0}%</p>
              </div>
              <div>
                <label className="text-slate-400 text-sm">Retries</label>
                <p className="mt-1 text-white">{mission.retry_count}/{mission.max_retries}</p>
              </div>
            </div>

            {mission.payload && Object.keys(mission.payload).length > 0 && (
              <div>
                <label className="text-slate-400 text-sm">Payload</label>
                <pre className="mt-1 bg-slate-900 text-slate-300 p-3 rounded text-sm overflow-auto max-h-32">
                  {JSON.stringify(mission.payload, null, 2)}
                </pre>
              </div>
            )}

            {mission.result && (
              <div>
                <label className="text-slate-400 text-sm">Result</label>
                <pre className="mt-1 bg-slate-900 text-slate-300 p-3 rounded text-sm overflow-auto max-h-32">
                  {JSON.stringify(mission.result, null, 2)}
                </pre>
              </div>
            )}

            {mission.error_message && (
              <div>
                <label className="text-slate-400 text-sm">Error</label>
                <p className="mt-1 text-red-400">{mission.error_message}</p>
              </div>
            )}

            <div className="flex items-center gap-3 pt-4 border-t border-slate-700">
              {(mission.status === 'pending' || mission.status === 'running') && (
                <button
                  onClick={onCancel}
                  className="px-4 py-2 bg-red-600 hover:bg-red-500 text-white rounded-lg"
                >
                  Cancel Mission
                </button>
              )}
              {mission.status === 'failed' && mission.retry_count < mission.max_retries && (
                <button
                  onClick={onRetry}
                  className="px-4 py-2 bg-yellow-600 hover:bg-yellow-500 text-white rounded-lg"
                >
                  Retry Mission
                </button>
              )}
              <button
                onClick={onClose}
                className="px-4 py-2 bg-slate-600 hover:bg-slate-500 text-white rounded-lg"
              >
                Close
              </button>
            </div>
          </div>
        </div>
      </div>
    </div>
  )
}

export default MissionDashboard
