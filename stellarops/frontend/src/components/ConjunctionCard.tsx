import type { Conjunction, CourseOfAction } from '../types'

interface ConjunctionCardProps {
  conjunction: Conjunction
  coas?: CourseOfAction[]
  isSelected?: boolean
  onSelect?: () => void
  onApproveCOA?: (coaId: string) => void
  onRejectCOA?: (coaId: string) => void
  compact?: boolean
}

const SEVERITY_STYLES = {
  low: {
    bg: 'bg-green-900/30',
    border: 'border-green-500',
    text: 'text-green-400',
    badge: 'bg-green-500/20 text-green-400'
  },
  medium: {
    bg: 'bg-amber-900/30',
    border: 'border-amber-500',
    text: 'text-amber-400',
    badge: 'bg-amber-500/20 text-amber-400'
  },
  high: {
    bg: 'bg-red-900/30',
    border: 'border-red-500',
    text: 'text-red-400',
    badge: 'bg-red-500/20 text-red-400'
  },
  critical: {
    bg: 'bg-red-950/50',
    border: 'border-red-600',
    text: 'text-red-300',
    badge: 'bg-red-500/30 text-red-300 animate-pulse'
  }
}

const STATUS_LABELS: Record<string, { label: string; class: string }> = {
  predicted: { label: 'Predicted', class: 'bg-blue-500/20 text-blue-400' },
  active: { label: 'Active', class: 'bg-orange-500/20 text-orange-400' },
  monitoring: { label: 'Monitoring', class: 'bg-purple-500/20 text-purple-400' },
  avoided: { label: 'Avoided', class: 'bg-green-500/20 text-green-400' },
  passed: { label: 'Passed', class: 'bg-gray-500/20 text-gray-400' },
  maneuver_executed: { label: 'Maneuver', class: 'bg-cyan-500/20 text-cyan-400' }
}

export function ConjunctionCard({
  conjunction,
  coas = [],
  isSelected = false,
  onSelect,
  onApproveCOA,
  onRejectCOA,
  compact = false
}: ConjunctionCardProps) {
  const styles = SEVERITY_STYLES[conjunction.severity]
  const statusInfo = STATUS_LABELS[conjunction.status] || STATUS_LABELS.predicted
  
  // Calculate time to TCA
  const tcaDate = new Date(conjunction.tca)
  const now = new Date()
  const hoursToTca = Math.max(0, (tcaDate.getTime() - now.getTime()) / (1000 * 60 * 60))
  const daysToTca = Math.floor(hoursToTca / 24)
  const remainingHours = Math.floor(hoursToTca % 24)

  const formatTcaCountdown = () => {
    if (hoursToTca <= 0) return 'PASSED'
    if (daysToTca > 0) return `${daysToTca}d ${remainingHours}h`
    if (hoursToTca < 1) return `${Math.floor(hoursToTca * 60)}m`
    return `${Math.floor(hoursToTca)}h`
  }

  const formatMissDistance = (meters: number) => {
    if (meters >= 1000) return `${(meters / 1000).toFixed(2)} km`
    return `${meters.toFixed(0)} m`
  }

  const recommendedCoa = coas.find(c => c.status === 'proposed' || c.status === 'approved')

  if (compact) {
    return (
      <div
        className={`${styles.bg} border ${styles.border} rounded-lg p-3 cursor-pointer transition-all
          ${isSelected ? 'ring-2 ring-white' : 'hover:opacity-90'}`}
        onClick={onSelect}
      >
        <div className="flex justify-between items-start">
          <div className="flex-1">
            <div className="flex items-center gap-2">
              <span className={`text-xs font-semibold px-2 py-0.5 rounded ${styles.badge}`}>
                {conjunction.severity.toUpperCase()}
              </span>
              <span className={`text-xs px-2 py-0.5 rounded ${statusInfo.class}`}>
                {statusInfo.label}
              </span>
            </div>
            <div className="mt-2 text-white text-sm font-medium truncate">
              {conjunction.primary_object?.name || 'Primary'} ↔ {conjunction.secondary_object?.name || 'Secondary'}
            </div>
          </div>
          <div className="text-right">
            <div className={`text-lg font-bold ${styles.text}`}>
              {formatTcaCountdown()}
            </div>
            <div className="text-xs text-gray-400">to TCA</div>
          </div>
        </div>
        <div className="mt-2 flex justify-between text-xs text-gray-400">
          <span>Miss: {formatMissDistance(conjunction.miss_distance.total_m)}</span>
          {conjunction.collision_probability && (
            <span>Pc: {conjunction.collision_probability.toExponential(2)}</span>
          )}
        </div>
      </div>
    )
  }

  return (
    <div
      className={`${styles.bg} border ${styles.border} rounded-xl p-4 transition-all
        ${isSelected ? 'ring-2 ring-white shadow-lg' : ''}`}
    >
      {/* Header */}
      <div className="flex justify-between items-start mb-4">
        <div>
          <div className="flex items-center gap-2">
            <span className={`text-sm font-bold px-3 py-1 rounded ${styles.badge}`}>
              {conjunction.severity.toUpperCase()}
            </span>
            <span className={`text-xs px-2 py-1 rounded ${statusInfo.class}`}>
              {statusInfo.label}
            </span>
          </div>
          <h3 className="mt-2 text-white font-semibold">
            Conjunction Event
          </h3>
        </div>
        <div className="text-right">
          <div className={`text-2xl font-bold ${styles.text}`}>
            {formatTcaCountdown()}
          </div>
          <div className="text-xs text-gray-400">Time to TCA</div>
        </div>
      </div>

      {/* Objects involved */}
      <div className="grid grid-cols-2 gap-4 mb-4">
        <div className="bg-slate-800/50 rounded-lg p-3">
          <div className="text-xs text-gray-400 mb-1">Primary (Protected)</div>
          <div className="text-white font-medium truncate">
            {conjunction.primary_object?.name || 'Unknown'}
          </div>
          <div className="text-xs text-gray-500">
            NORAD: {conjunction.primary_object?.norad_id}
          </div>
        </div>
        <div className="bg-slate-800/50 rounded-lg p-3">
          <div className="text-xs text-gray-400 mb-1">Secondary</div>
          <div className="text-white font-medium truncate">
            {conjunction.secondary_object?.name || 'Unknown'}
          </div>
          <div className="text-xs text-gray-500">
            NORAD: {conjunction.secondary_object?.norad_id} • 
            <span className={`ml-1 ${conjunction.secondary_object?.threat_level === 'high' ? 'text-red-400' : 'text-gray-400'}`}>
              {conjunction.secondary_object?.object_type}
            </span>
          </div>
        </div>
      </div>

      {/* Key metrics */}
      <div className="grid grid-cols-3 gap-3 mb-4">
        <div className="text-center">
          <div className="text-xs text-gray-400">Miss Distance</div>
          <div className={`text-lg font-bold ${conjunction.miss_distance.total_m < 500 ? 'text-red-400' : 'text-white'}`}>
            {formatMissDistance(conjunction.miss_distance.total_m)}
          </div>
        </div>
        <div className="text-center">
          <div className="text-xs text-gray-400">Collision Prob</div>
          <div className={`text-lg font-bold ${(conjunction.collision_probability || 0) > 1e-5 ? 'text-red-400' : 'text-white'}`}>
            {conjunction.collision_probability 
              ? conjunction.collision_probability.toExponential(2) 
              : 'N/A'}
          </div>
        </div>
        <div className="text-center">
          <div className="text-xs text-gray-400">Rel Velocity</div>
          <div className="text-lg font-bold text-white">
            {conjunction.relative_velocity_ms 
              ? `${(conjunction.relative_velocity_ms / 1000).toFixed(2)} km/s`
              : 'N/A'}
          </div>
        </div>
      </div>

      {/* TCA details */}
      <div className="bg-slate-800/50 rounded-lg p-3 mb-4">
        <div className="flex justify-between text-sm">
          <span className="text-gray-400">TCA:</span>
          <span className="text-white">
            {tcaDate.toLocaleString()}
          </span>
        </div>
        {conjunction.tca_uncertainty_seconds > 0 && (
          <div className="flex justify-between text-sm">
            <span className="text-gray-400">Uncertainty:</span>
            <span className="text-gray-300">
              ±{conjunction.tca_uncertainty_seconds.toFixed(1)}s
            </span>
          </div>
        )}
      </div>

      {/* COA Recommendation */}
      {recommendedCoa && (
        <div className="border-t border-slate-700 pt-4">
          <div className="flex items-center justify-between mb-3">
            <div className="text-sm font-medium text-gray-300">
              Recommended Action
            </div>
            <span className={`text-xs px-2 py-1 rounded ${
              recommendedCoa.coa_type === 'avoidance_maneuver' 
                ? 'bg-cyan-500/20 text-cyan-400'
                : 'bg-gray-500/20 text-gray-400'
            }`}>
              {recommendedCoa.coa_type.replace('_', ' ').toUpperCase()}
            </span>
          </div>
          
          <div className="bg-slate-800/50 rounded-lg p-3 mb-3">
            <div className="text-white font-medium mb-1">{recommendedCoa.title}</div>
            <div className="text-sm text-gray-400">{recommendedCoa.description}</div>
            
            {recommendedCoa.maneuver.delta_v_ms && (
              <div className="mt-2 grid grid-cols-2 gap-2 text-xs">
                <div>
                  <span className="text-gray-500">Delta-V:</span>
                  <span className="text-white ml-1">{recommendedCoa.maneuver.delta_v_ms.toFixed(3)} m/s</span>
                </div>
                <div>
                  <span className="text-gray-500">Fuel:</span>
                  <span className="text-white ml-1">{recommendedCoa.maneuver.fuel_cost_kg?.toFixed(3)} kg</span>
                </div>
              </div>
            )}
            
            <div className="mt-2 flex justify-between text-xs">
              <span className="text-gray-500">Effectiveness:</span>
              <div className="flex items-center gap-2">
                <div className="w-20 h-2 bg-slate-700 rounded-full overflow-hidden">
                  <div 
                    className="h-full bg-green-500" 
                    style={{ width: `${(recommendedCoa.scores.effectiveness || 0) * 100}%` }}
                  />
                </div>
                <span className="text-white">{((recommendedCoa.scores.effectiveness || 0) * 100).toFixed(0)}%</span>
              </div>
            </div>
          </div>

          {recommendedCoa.status === 'proposed' && onApproveCOA && onRejectCOA && (
            <div className="flex gap-2">
              <button
                onClick={() => onApproveCOA(recommendedCoa.id)}
                className="flex-1 bg-green-600 hover:bg-green-500 text-white py-2 rounded-lg font-medium transition-colors"
              >
                Approve
              </button>
              <button
                onClick={() => onRejectCOA(recommendedCoa.id)}
                className="flex-1 bg-slate-600 hover:bg-slate-500 text-white py-2 rounded-lg font-medium transition-colors"
              >
                Reject
              </button>
            </div>
          )}
        </div>
      )}

      {/* View details link */}
      {onSelect && (
        <button
          onClick={onSelect}
          className="mt-3 w-full text-center text-sm text-blue-400 hover:text-blue-300 transition-colors"
        >
          View Full Details →
        </button>
      )}
    </div>
  )
}

export default ConjunctionCard
