import { useState, useEffect } from 'react'
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import { api } from '../services/api'
import { useSatelliteStore } from '../store/satelliteStore'
import { SatelliteCard } from '../components'
import type { Satellite, SatelliteMode } from '../types'

export default function SatelliteList() {
  const queryClient = useQueryClient()
  const { satellites, setSatellites } = useSatelliteStore()
  const [showCreateModal, setShowCreateModal] = useState(false)
  const [filterMode, setFilterMode] = useState<SatelliteMode | 'all'>('all')
  const [searchQuery, setSearchQuery] = useState('')

  // Fetch satellites
  const { data: satelliteList, isLoading, error, refetch } = useQuery({
    queryKey: ['satellites'],
    queryFn: api.satellites.list,
  })

  // Create satellite mutation
  const createMutation = useMutation({
    mutationFn: (newSatellite: Partial<Satellite>) => api.satellites.create(newSatellite),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['satellites'] })
      setShowCreateModal(false)
    },
  })

  // Update store when data changes
  useEffect(() => {
    if (satelliteList) {
      setSatellites(satelliteList)
    }
  }, [satelliteList, setSatellites])

  // Filter and search satellites
  const satelliteArray = Array.from(satellites.values())
  const filteredSatellites = satelliteArray.filter((sat) => {
    const matchesMode = filterMode === 'all' || sat.mode === filterMode
    const matchesSearch = sat.id.toLowerCase().includes(searchQuery.toLowerCase())
    return matchesMode && matchesSearch
  })

  // Group by mode
  const groupedByMode = {
    nominal: filteredSatellites.filter((s) => s.mode === 'nominal'),
    safe: filteredSatellites.filter((s) => s.mode === 'safe'),
    critical: filteredSatellites.filter((s) => s.mode === 'critical'),
    standby: filteredSatellites.filter((s) => s.mode === 'standby'),
  }

  if (isLoading) {
    return (
      <div className="flex items-center justify-center h-96">
        <div className="text-stellar-400 text-lg">Loading satellites...</div>
      </div>
    )
  }

  if (error) {
    return (
      <div className="flex items-center justify-center h-96">
        <div className="text-red-400 text-lg">
          Error loading satellites: {(error as Error).message}
        </div>
      </div>
    )
  }

  return (
    <div className="space-y-6">
      {/* Header */}
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-3xl font-bold text-white">Satellites</h1>
          <p className="text-slate-400 mt-1">
            {filteredSatellites.length} of {satelliteArray.length} satellites
          </p>
        </div>
        <div className="flex items-center gap-3">
          <button
            onClick={() => refetch()}
            className="px-4 py-2 bg-slate-700 hover:bg-slate-600 text-white rounded-lg transition-colors"
          >
            ↻ Refresh
          </button>
          <button
            onClick={() => setShowCreateModal(true)}
            className="px-4 py-2 bg-stellar-600 hover:bg-stellar-500 text-white rounded-lg transition-colors"
          >
            + Add Satellite
          </button>
        </div>
      </div>

      {/* Filters */}
      <div className="flex flex-wrap items-center gap-4">
        <input
          type="text"
          placeholder="Search satellites..."
          value={searchQuery}
          onChange={(e) => setSearchQuery(e.target.value)}
          className="px-4 py-2 bg-slate-800 border border-slate-700 rounded-lg text-white placeholder-slate-400 focus:outline-none focus:border-stellar-500 w-64"
        />
        <div className="flex items-center gap-2">
          <span className="text-slate-400 text-sm">Filter:</span>
          {(['all', 'nominal', 'safe', 'critical', 'standby'] as const).map((mode) => (
            <button
              key={mode}
              onClick={() => setFilterMode(mode)}
              className={`px-3 py-1 rounded-full text-sm transition-colors ${
                filterMode === mode
                  ? 'bg-stellar-600 text-white'
                  : 'bg-slate-700 text-slate-300 hover:bg-slate-600'
              }`}
            >
              {mode === 'all' ? 'All' : mode.charAt(0).toUpperCase() + mode.slice(1)}
              {mode !== 'all' && (
                <span className="ml-1 opacity-70">
                  ({groupedByMode[mode as SatelliteMode].length})
                </span>
              )}
            </button>
          ))}
        </div>
      </div>

      {/* Satellite Grid */}
      {filteredSatellites.length > 0 ? (
        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4 gap-4">
          {filteredSatellites.map((satellite) => (
            <SatelliteCard key={satellite.id} satellite={satellite} />
          ))}
        </div>
      ) : (
        <div className="bg-slate-800 rounded-xl p-12 border border-slate-700 text-center">
          <div className="text-4xl mb-4">🔍</div>
          <h3 className="text-xl font-semibold text-white mb-2">No Satellites Found</h3>
          <p className="text-slate-400">
            {searchQuery || filterMode !== 'all'
              ? 'Try adjusting your search or filters.'
              : 'No satellites are currently in the constellation.'}
          </p>
        </div>
      )}

      {/* Create Modal */}
      {showCreateModal && (
        <CreateSatelliteModal
          onClose={() => setShowCreateModal(false)}
          onSubmit={(data) => createMutation.mutate(data)}
          isLoading={createMutation.isPending}
          error={createMutation.error?.message}
        />
      )}
    </div>
  )
}

// Create Satellite Modal
interface CreateSatelliteModalProps {
  onClose: () => void
  onSubmit: (data: Partial<Satellite>) => void
  isLoading: boolean
  error?: string
}

function CreateSatelliteModal({ onClose, onSubmit, isLoading, error }: CreateSatelliteModalProps) {
  const [formData, setFormData] = useState({
    id: '',
    mode: 'nominal' as SatelliteMode,
    energy: 100,
    memory: 0,
  })

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault()
    if (!formData.id.trim()) return
    onSubmit(formData)
  }

  return (
    <div className="fixed inset-0 bg-black/50 flex items-center justify-center z-50">
      <div className="bg-slate-800 rounded-xl p-6 w-full max-w-md border border-slate-700">
        <h2 className="text-xl font-bold text-white mb-4">Add New Satellite</h2>
        
        <form onSubmit={handleSubmit} className="space-y-4">
          <div>
            <label className="block text-sm text-slate-400 mb-1">Satellite ID</label>
            <input
              type="text"
              value={formData.id}
              onChange={(e) => setFormData({ ...formData, id: e.target.value })}
              placeholder="SAT-001"
              className="w-full px-4 py-2 bg-slate-700 border border-slate-600 rounded-lg text-white placeholder-slate-400 focus:outline-none focus:border-stellar-500"
              required
            />
          </div>

          <div>
            <label className="block text-sm text-slate-400 mb-1">Initial Mode</label>
            <select
              value={formData.mode}
              onChange={(e) => setFormData({ ...formData, mode: e.target.value as SatelliteMode })}
              className="w-full px-4 py-2 bg-slate-700 border border-slate-600 rounded-lg text-white focus:outline-none focus:border-stellar-500"
            >
              <option value="nominal">Nominal</option>
              <option value="safe">Safe</option>
              <option value="standby">Standby</option>
            </select>
          </div>

          <div className="grid grid-cols-2 gap-4">
            <div>
              <label className="block text-sm text-slate-400 mb-1">Energy (%)</label>
              <input
                type="number"
                value={formData.energy}
                onChange={(e) => setFormData({ ...formData, energy: Number(e.target.value) })}
                min={0}
                max={100}
                className="w-full px-4 py-2 bg-slate-700 border border-slate-600 rounded-lg text-white focus:outline-none focus:border-stellar-500"
              />
            </div>
            <div>
              <label className="block text-sm text-slate-400 mb-1">Memory (%)</label>
              <input
                type="number"
                value={formData.memory}
                onChange={(e) => setFormData({ ...formData, memory: Number(e.target.value) })}
                min={0}
                max={100}
                className="w-full px-4 py-2 bg-slate-700 border border-slate-600 rounded-lg text-white focus:outline-none focus:border-stellar-500"
              />
            </div>
          </div>

          {error && (
            <div className="text-red-400 text-sm">{error}</div>
          )}

          <div className="flex items-center gap-3 pt-4">
            <button
              type="button"
              onClick={onClose}
              className="flex-1 px-4 py-2 bg-slate-700 hover:bg-slate-600 text-white rounded-lg transition-colors"
              disabled={isLoading}
            >
              Cancel
            </button>
            <button
              type="submit"
              className="flex-1 px-4 py-2 bg-stellar-600 hover:bg-stellar-500 text-white rounded-lg transition-colors disabled:opacity-50"
              disabled={isLoading || !formData.id.trim()}
            >
              {isLoading ? 'Creating...' : 'Create Satellite'}
            </button>
          </div>
        </form>
      </div>
    </div>
  )
}
