import { useState, useEffect } from 'react'
import { useConjunctions, useConjunction, getSeverityColor, formatTCACountdown } from '../hooks/useConjunctions'
import { useCOAs } from '../hooks/useCOAs'
import type { Conjunction, ConjunctionSeverity } from '../types'
import COAList from '../components/COAList'

type SortField = 'severity' | 'tca' | 'miss_distance'
type SortOrder = 'asc' | 'desc'

export default function ThreatDashboard() {
  const [selectedId, setSelectedId] = useState<string | null>(null)
  const [severityFilter, setSeverityFilter] = useState<ConjunctionSeverity | 'all'>('all')
  const [sortField, setSortField] = useState<SortField>('tca')
  const [sortOrder, setSortOrder] = useState<SortOrder>('asc')

  // Fetch all conjunctions
  const { conjunctions, loading: listLoading, error: listError } = useConjunctions({
    status: 'detected,monitoring,acknowledged',
  })

  // Fetch selected conjunction details
  const { conjunction, loading: detailLoading } = useConjunction(selectedId)

  // Fetch COAs for selected conjunction
  const { coas, loading: coasLoading, refetch: refetchCOAs } = useCOAs(selectedId)

  // Auto-select first conjunction
  useEffect(() => {
    if (!selectedId && conjunctions.length > 0) {
      setSelectedId(conjunctions[0].id)
    }
  }, [conjunctions, selectedId])

  // Filter and sort conjunctions
  const filteredConjunctions = conjunctions
    .filter(c => severityFilter === 'all' || c.severity === severityFilter)
    .sort((a, b) => {
      let comparison = 0
      switch (sortField) {
        case 'severity':
          const severityOrder = { critical: 0, high: 1, medium: 2, low: 3 }
          comparison = severityOrder[a.severity] - severityOrder[b.severity]
          break
        case 'tca':
          comparison = new Date(a.tca).getTime() - new Date(b.tca).getTime()
          break
        case 'miss_distance':
          comparison = a.miss_distance_km - b.miss_distance_km
          break
      }
      return sortOrder === 'asc' ? comparison : -comparison
    })

  // Real-time TCA countdown
  const [, setTick] = useState(0)
  useEffect(() => {
    const interval = setInterval(() => setTick(t => t + 1), 1000)
    return () => clearInterval(interval)
  }, [])

  return (
    <div className="h-[calc(100vh-200px)] flex gap-4">
      {/* Left Panel: Conjunction List */}
      <div className="w-96 flex-shrink-0 bg-slate-800 rounded-lg border border-slate-700 flex flex-col">
        {/* Header */}
        <div className="p-4 border-b border-slate-700">
          <h2 className="text-lg font-semibold text-white mb-3">Active Conjunctions</h2>
          
          {/* Filters */}
          <div className="flex gap-2 mb-3">
            <select
              value={severityFilter}
              onChange={(e) => setSeverityFilter(e.target.value as ConjunctionSeverity | 'all')}
              className="flex-1 bg-slate-700 text-slate-200 rounded px-2 py-1 text-sm border border-slate-600"
            >
              <option value="all">All Severities</option>
              <option value="critical">Critical</option>
              <option value="high">High</option>
              <option value="medium">Medium</option>
              <option value="low">Low</option>
            </select>
          </div>

          {/* Sort Options */}
          <div className="flex gap-2">
            <select
              value={sortField}
              onChange={(e) => setSortField(e.target.value as SortField)}
              className="flex-1 bg-slate-700 text-slate-200 rounded px-2 py-1 text-sm border border-slate-600"
            >
              <option value="tca">Sort by TCA</option>
              <option value="severity">Sort by Severity</option>
              <option value="miss_distance">Sort by Miss Distance</option>
            </select>
            <button
              onClick={() => setSortOrder(o => o === 'asc' ? 'desc' : 'asc')}
              className="px-2 py-1 bg-slate-700 rounded border border-slate-600 text-slate-300 hover:bg-slate-600"
            >
              {sortOrder === 'asc' ? '↑' : '↓'}
            </button>
          </div>
        </div>

        {/* Conjunction List */}
        <div className="flex-1 overflow-y-auto">
          {listLoading ? (
            <div className="p-4 text-center text-slate-400">Loading...</div>
          ) : listError ? (
            <div className="p-4 text-center text-red-400">{listError}</div>
          ) : filteredConjunctions.length === 0 ? (
            <div className="p-4 text-center text-slate-400">No active conjunctions</div>
          ) : (
            filteredConjunctions.map((conj) => (
              <ConjunctionListItem
                key={conj.id}
                conjunction={conj}
                isSelected={conj.id === selectedId}
                onClick={() => setSelectedId(conj.id)}
              />
            ))
          )}
        </div>
      </div>

      {/* Right Panel: Conjunction Detail */}
      <div className="flex-1 bg-slate-800 rounded-lg border border-slate-700 flex flex-col overflow-hidden">
        {detailLoading ? (
          <div className="flex-1 flex items-center justify-center text-slate-400">
            Loading conjunction details...
          </div>
        ) : conjunction ? (
          <>
            {/* Detail Header */}
            <div className="p-4 border-b border-slate-700">
              <div className="flex items-center justify-between">
                <div>
                  <h2 className="text-xl font-semibold text-white">
                    {conjunction.asset?.name || conjunction.asset_id} vs {conjunction.object?.name || conjunction.object_id}
                  </h2>
                  <p className="text-sm text-slate-400">
                    NORAD: {conjunction.object?.norad_id || 'Unknown'}
                  </p>
                </div>
                <div className={`px-3 py-1 rounded-full text-sm font-medium uppercase ${getSeverityColor(conjunction.severity)}`}>
                  {conjunction.severity}
                </div>
              </div>
            </div>

            {/* Detail Content */}
            <div className="flex-1 overflow-y-auto p-4 grid grid-cols-2 gap-4">
              {/* Conjunction Metrics */}
              <div className="col-span-2 bg-slate-700/50 rounded-lg p-4">
                <h3 className="text-sm font-medium text-slate-400 mb-3">Conjunction Metrics</h3>
                <div className="grid grid-cols-4 gap-4">
                  <MetricCard
                    label="Time to TCA"
                    value={formatTCACountdown(conjunction.tca)}
                    subValue={new Date(conjunction.tca).toLocaleString()}
                    highlight={conjunction.severity === 'critical'}
                  />
                  <MetricCard
                    label="Miss Distance"
                    value={`${conjunction.miss_distance_km.toFixed(3)} km`}
                    subValue={`${(conjunction.miss_distance_km * 1000).toFixed(0)} m`}
                  />
                  <MetricCard
                    label="Relative Velocity"
                    value={`${conjunction.relative_velocity_km_s.toFixed(2)} km/s`}
                    subValue={`${(conjunction.relative_velocity_km_s * 1000).toFixed(0)} m/s`}
                  />
                  <MetricCard
                    label="Collision Probability"
                    value={conjunction.probability < 0.0001 
                      ? '< 0.01%' 
                      : `${(conjunction.probability * 100).toFixed(2)}%`}
                    subValue={`1 in ${Math.round(1 / conjunction.probability).toLocaleString()}`}
                    highlight={conjunction.probability > 0.001}
                  />
                </div>
              </div>

              {/* Threat Assessment */}
              {conjunction.threat_assessment && (
                <div className="bg-slate-700/50 rounded-lg p-4">
                  <h3 className="text-sm font-medium text-slate-400 mb-3">Threat Assessment</h3>
                  <div className="space-y-2">
                    <div className="flex justify-between">
                      <span className="text-slate-400">Classification:</span>
                      <span className={`font-medium ${
                        conjunction.threat_assessment.classification === 'hostile' ? 'text-red-400' :
                        conjunction.threat_assessment.classification === 'suspicious' ? 'text-orange-400' :
                        'text-slate-200'
                      }`}>
                        {conjunction.threat_assessment.classification.toUpperCase()}
                      </span>
                    </div>
                    <div className="flex justify-between">
                      <span className="text-slate-400">Threat Level:</span>
                      <span className="text-slate-200">{conjunction.threat_assessment.threat_level}</span>
                    </div>
                    <div className="flex justify-between">
                      <span className="text-slate-400">Confidence:</span>
                      <span className="text-slate-200">{conjunction.threat_assessment.confidence_level}</span>
                    </div>
                    {conjunction.threat_assessment.capabilities.length > 0 && (
                      <div>
                        <span className="text-slate-400 text-sm">Capabilities:</span>
                        <div className="flex flex-wrap gap-1 mt-1">
                          {conjunction.threat_assessment.capabilities.map((cap) => (
                            <span key={cap} className="px-2 py-0.5 bg-slate-600 rounded text-xs text-slate-300">
                              {cap}
                            </span>
                          ))}
                        </div>
                      </div>
                    )}
                  </div>
                </div>
              )}

              {/* Object Info */}
              <div className="bg-slate-700/50 rounded-lg p-4">
                <h3 className="text-sm font-medium text-slate-400 mb-3">Threat Object</h3>
                <div className="space-y-2 text-sm">
                  <div className="flex justify-between">
                    <span className="text-slate-400">Name:</span>
                    <span className="text-slate-200">{conjunction.object?.name || 'Unknown'}</span>
                  </div>
                  <div className="flex justify-between">
                    <span className="text-slate-400">NORAD ID:</span>
                    <span className="text-slate-200 font-mono">{conjunction.object?.norad_id}</span>
                  </div>
                  <div className="flex justify-between">
                    <span className="text-slate-400">Type:</span>
                    <span className="text-slate-200">{conjunction.object?.object_type}</span>
                  </div>
                  {conjunction.object?.owner && (
                    <div className="flex justify-between">
                      <span className="text-slate-400">Owner:</span>
                      <span className="text-slate-200">{conjunction.object.owner}</span>
                    </div>
                  )}
                  {conjunction.object?.rcs_meters && (
                    <div className="flex justify-between">
                      <span className="text-slate-400">RCS:</span>
                      <span className="text-slate-200">{conjunction.object.rcs_meters.toFixed(2)} m²</span>
                    </div>
                  )}
                </div>
              </div>

              {/* Positions at TCA */}
              <div className="col-span-2 bg-slate-700/50 rounded-lg p-4">
                <h3 className="text-sm font-medium text-slate-400 mb-3">Predicted Positions at TCA</h3>
                <div className="grid grid-cols-2 gap-4">
                  <div>
                    <h4 className="text-xs text-slate-500 mb-2">Asset Position</h4>
                    {conjunction.asset_position_at_tca ? (
                      <div className="font-mono text-sm text-slate-300">
                        <div>X: {conjunction.asset_position_at_tca.x_km.toFixed(3)} km</div>
                        <div>Y: {conjunction.asset_position_at_tca.y_km.toFixed(3)} km</div>
                        <div>Z: {conjunction.asset_position_at_tca.z_km.toFixed(3)} km</div>
                      </div>
                    ) : (
                      <span className="text-slate-500">Not available</span>
                    )}
                  </div>
                  <div>
                    <h4 className="text-xs text-slate-500 mb-2">Object Position</h4>
                    {conjunction.object_position_at_tca ? (
                      <div className="font-mono text-sm text-slate-300">
                        <div>X: {conjunction.object_position_at_tca.x_km.toFixed(3)} km</div>
                        <div>Y: {conjunction.object_position_at_tca.y_km.toFixed(3)} km</div>
                        <div>Z: {conjunction.object_position_at_tca.z_km.toFixed(3)} km</div>
                      </div>
                    ) : (
                      <span className="text-slate-500">Not available</span>
                    )}
                  </div>
                </div>
              </div>

              {/* COA Section */}
              <div className="col-span-2">
                <COAList
                  conjunctionId={conjunction.id}
                  coas={coas}
                  loading={coasLoading}
                  onRefetch={refetchCOAs}
                />
              </div>
            </div>
          </>
        ) : (
          <div className="flex-1 flex items-center justify-center text-slate-400">
            Select a conjunction to view details
          </div>
        )}
      </div>
    </div>
  )
}

// Conjunction List Item Component
interface ConjunctionListItemProps {
  conjunction: Conjunction
  isSelected: boolean
  onClick: () => void
}

function ConjunctionListItem({ conjunction, isSelected, onClick }: ConjunctionListItemProps) {
  return (
    <button
      onClick={onClick}
      className={`w-full p-3 border-b border-slate-700 text-left transition-colors ${
        isSelected ? 'bg-stellar-600/20 border-l-2 border-l-stellar-500' : 'hover:bg-slate-700/50'
      }`}
    >
      <div className="flex items-start justify-between mb-1">
        <span className="text-sm font-medium text-white truncate">
          {conjunction.asset?.name || conjunction.asset_id}
        </span>
        <span className={`px-2 py-0.5 rounded text-xs font-medium uppercase ${getSeverityColor(conjunction.severity)}`}>
          {conjunction.severity}
        </span>
      </div>
      <div className="text-xs text-slate-400 mb-2 truncate">
        vs {conjunction.object?.name || conjunction.object_id}
      </div>
      <div className="flex items-center justify-between text-xs">
        <span className="text-slate-500">TCA:</span>
        <span className="font-mono text-stellar-400">
          {formatTCACountdown(conjunction.tca)}
        </span>
      </div>
      <div className="flex items-center justify-between text-xs mt-1">
        <span className="text-slate-500">Miss:</span>
        <span className="font-mono text-slate-300">
          {conjunction.miss_distance_km < 1 
            ? `${(conjunction.miss_distance_km * 1000).toFixed(0)} m`
            : `${conjunction.miss_distance_km.toFixed(2)} km`}
        </span>
      </div>
    </button>
  )
}

// Metric Card Component
interface MetricCardProps {
  label: string
  value: string
  subValue?: string
  highlight?: boolean
}

function MetricCard({ label, value, subValue, highlight }: MetricCardProps) {
  return (
    <div className={`p-3 rounded-lg ${highlight ? 'bg-red-500/20 border border-red-500/50' : 'bg-slate-600/50'}`}>
      <div className="text-xs text-slate-400 mb-1">{label}</div>
      <div className={`text-lg font-semibold ${highlight ? 'text-red-400' : 'text-white'}`}>
        {value}
      </div>
      {subValue && (
        <div className="text-xs text-slate-500 mt-0.5">{subValue}</div>
      )}
    </div>
  )
}
