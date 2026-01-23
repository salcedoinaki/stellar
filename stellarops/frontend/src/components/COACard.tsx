import { useState } from 'react'
import type { COA, COASimulationResult } from '../types'
import { getCOATypeInfo, getRiskScoreColor, formatDeltaV, useSimulateCOA, useSelectCOA } from '../hooks/useCOAs'

interface COACardProps {
  coa: COA
  isRecommended?: boolean
  onSelect?: () => void
}

export default function COACard({ coa, isRecommended, onSelect }: COACardProps) {
  const [expanded, setExpanded] = useState(false)
  const [showConfirmation, setShowConfirmation] = useState(false)
  const [showSimulation, setShowSimulation] = useState(false)

  const { simulation, loading: simLoading, simulate, clearSimulation } = useSimulateCOA()
  const { selectCOA, loading: selectLoading } = useSelectCOA()

  const typeInfo = getCOATypeInfo(coa.type)
  const isSelectable = coa.status === 'proposed'
  const isActive = coa.status === 'selected' || coa.status === 'executing'

  const handleSimulate = async () => {
    await simulate(coa.id)
    setShowSimulation(true)
  }

  const handleSelect = async () => {
    const result = await selectCOA(coa.id)
    if (result) {
      setShowConfirmation(false)
      onSelect?.()
    }
  }

  return (
    <>
      <div className={`rounded-lg border ${
        isRecommended ? 'border-stellar-500 bg-stellar-500/10' :
        isActive ? 'border-green-500 bg-green-500/10' :
        coa.status === 'failed' ? 'border-red-500 bg-red-500/10' :
        coa.status === 'rejected' ? 'border-slate-600 bg-slate-700/30 opacity-60' :
        'border-slate-600 bg-slate-700/50'
      }`}>
        {/* Header */}
        <div className="p-3 border-b border-slate-600/50">
          <div className="flex items-center justify-between">
            <div className="flex items-center gap-2">
              <span className="text-xl">{typeInfo.icon}</span>
              <div>
                <h4 className={`font-medium ${typeInfo.color}`}>{typeInfo.label}</h4>
                {isRecommended && (
                  <span className="text-xs text-stellar-400">⭐ Recommended</span>
                )}
              </div>
            </div>
            <div className={`px-2 py-1 rounded text-sm font-bold ${getRiskScoreColor(coa.risk_score)}`}>
              Risk: {coa.risk_score.toFixed(0)}
            </div>
          </div>
        </div>

        {/* Main Content */}
        <div className="p-3 grid grid-cols-2 gap-3 text-sm">
          <div>
            <span className="text-slate-400">ΔV Required:</span>
            <span className="ml-2 text-white font-mono">{formatDeltaV(coa.delta_v_magnitude)}</span>
          </div>
          <div>
            <span className="text-slate-400">Fuel:</span>
            <span className="ml-2 text-white font-mono">
              {coa.estimated_fuel_kg?.toFixed(2) || '0.00'} kg
            </span>
          </div>
          <div>
            <span className="text-slate-400">Burn Time:</span>
            <span className="ml-2 text-white font-mono">
              {coa.burn_start_time 
                ? new Date(coa.burn_start_time).toLocaleTimeString() 
                : 'N/A'}
            </span>
          </div>
          <div>
            <span className="text-slate-400">Duration:</span>
            <span className="ml-2 text-white font-mono">
              {coa.burn_duration_seconds?.toFixed(0) || '0'}s
            </span>
          </div>
          <div className="col-span-2">
            <span className="text-slate-400">Predicted Miss:</span>
            <span className="ml-2 text-green-400 font-mono">
              {coa.predicted_miss_distance_km?.toFixed(2) || '?'} km
            </span>
          </div>
        </div>

        {/* Status Badge */}
        {coa.status !== 'proposed' && (
          <div className={`mx-3 mb-3 px-2 py-1 rounded text-xs text-center font-medium uppercase ${
            coa.status === 'selected' ? 'bg-blue-500/20 text-blue-400' :
            coa.status === 'executing' ? 'bg-yellow-500/20 text-yellow-400' :
            coa.status === 'completed' ? 'bg-green-500/20 text-green-400' :
            coa.status === 'failed' ? 'bg-red-500/20 text-red-400' :
            'bg-slate-600/50 text-slate-400'
          }`}>
            {coa.status}
            {coa.failure_reason && `: ${coa.failure_reason}`}
          </div>
        )}

        {/* Expanded Details */}
        {expanded && (
          <div className="px-3 pb-3 border-t border-slate-600/50 pt-3">
            <h5 className="text-xs text-slate-400 mb-2">Objective</h5>
            <p className="text-sm text-slate-300 mb-3">{coa.objective || coa.description || 'No description'}</p>

            {coa.pre_burn_orbit && (
              <div className="mb-3">
                <h5 className="text-xs text-slate-400 mb-1">Pre-Burn Orbit</h5>
                <div className="font-mono text-xs text-slate-300">
                  a: {coa.pre_burn_orbit.a.toFixed(1)} km | e: {coa.pre_burn_orbit.e.toFixed(4)} | i: {coa.pre_burn_orbit.i.toFixed(2)}°
                </div>
              </div>
            )}

            {coa.post_burn_orbit && (
              <div>
                <h5 className="text-xs text-slate-400 mb-1">Post-Burn Orbit</h5>
                <div className="font-mono text-xs text-slate-300">
                  a: {coa.post_burn_orbit.a.toFixed(1)} km | e: {coa.post_burn_orbit.e.toFixed(4)} | i: {coa.post_burn_orbit.i.toFixed(2)}°
                </div>
              </div>
            )}
          </div>
        )}

        {/* Actions */}
        <div className="p-3 border-t border-slate-600/50 flex gap-2">
          <button
            onClick={() => setExpanded(!expanded)}
            className="px-3 py-1.5 text-sm bg-slate-600 hover:bg-slate-500 rounded text-slate-200 transition-colors"
          >
            {expanded ? 'Less' : 'Details'}
          </button>
          
          {isSelectable && (
            <>
              <button
                onClick={handleSimulate}
                disabled={simLoading}
                className="px-3 py-1.5 text-sm bg-slate-600 hover:bg-slate-500 rounded text-slate-200 transition-colors disabled:opacity-50"
              >
                {simLoading ? 'Simulating...' : 'Simulate'}
              </button>
              <button
                onClick={() => setShowConfirmation(true)}
                disabled={selectLoading}
                className="px-3 py-1.5 text-sm bg-stellar-600 hover:bg-stellar-500 rounded text-white transition-colors disabled:opacity-50 ml-auto"
              >
                Select COA
              </button>
            </>
          )}
        </div>
      </div>

      {/* Selection Confirmation Modal */}
      {showConfirmation && (
        <ConfirmationModal
          title="Confirm COA Selection"
          message={`Are you sure you want to select "${typeInfo.label}"? This will create missions and may consume ${coa.estimated_fuel_kg?.toFixed(2) || '?'} kg of fuel.`}
          confirmLabel="Select & Execute"
          onConfirm={handleSelect}
          onCancel={() => setShowConfirmation(false)}
          loading={selectLoading}
        />
      )}

      {/* Simulation Results Modal */}
      {showSimulation && simulation && (
        <SimulationModal
          simulation={simulation}
          onClose={() => {
            setShowSimulation(false)
            clearSimulation()
          }}
        />
      )}
    </>
  )
}

// Confirmation Modal
interface ConfirmationModalProps {
  title: string
  message: string
  confirmLabel: string
  onConfirm: () => void
  onCancel: () => void
  loading?: boolean
}

function ConfirmationModal({ title, message, confirmLabel, onConfirm, onCancel, loading }: ConfirmationModalProps) {
  return (
    <div className="fixed inset-0 bg-black/50 flex items-center justify-center z-50">
      <div className="bg-slate-800 rounded-lg border border-slate-600 p-6 max-w-md w-full mx-4">
        <h3 className="text-lg font-semibold text-white mb-2">{title}</h3>
        <p className="text-slate-300 mb-6">{message}</p>
        <div className="flex gap-3 justify-end">
          <button
            onClick={onCancel}
            disabled={loading}
            className="px-4 py-2 bg-slate-600 hover:bg-slate-500 rounded text-slate-200 transition-colors"
          >
            Cancel
          </button>
          <button
            onClick={onConfirm}
            disabled={loading}
            className="px-4 py-2 bg-stellar-600 hover:bg-stellar-500 rounded text-white transition-colors disabled:opacity-50"
          >
            {loading ? 'Processing...' : confirmLabel}
          </button>
        </div>
      </div>
    </div>
  )
}

// Simulation Results Modal
interface SimulationModalProps {
  simulation: COASimulationResult
  onClose: () => void
}

function SimulationModal({ simulation, onClose }: SimulationModalProps) {
  const typeInfo = getCOATypeInfo(simulation.coa_type)

  return (
    <div className="fixed inset-0 bg-black/50 flex items-center justify-center z-50">
      <div className="bg-slate-800 rounded-lg border border-slate-600 p-6 max-w-2xl w-full mx-4 max-h-[80vh] overflow-y-auto">
        <div className="flex items-center justify-between mb-4">
          <h3 className="text-lg font-semibold text-white">
            Simulation Results: {typeInfo.label}
          </h3>
          <button onClick={onClose} className="text-slate-400 hover:text-white">✕</button>
        </div>

        <div className="grid grid-cols-2 gap-4 mb-6">
          <div className="bg-slate-700/50 rounded p-3">
            <div className="text-xs text-slate-400 mb-1">Original Miss Distance</div>
            <div className="text-lg font-mono text-white">
              {simulation.original_miss_distance_km.toFixed(3)} km
            </div>
          </div>
          <div className="bg-green-500/20 rounded p-3 border border-green-500/50">
            <div className="text-xs text-green-400 mb-1">Predicted Miss Distance</div>
            <div className="text-lg font-mono text-green-400">
              {simulation.predicted_miss_distance_km.toFixed(3)} km
            </div>
          </div>
          <div className="bg-slate-700/50 rounded p-3">
            <div className="text-xs text-slate-400 mb-1">Improvement</div>
            <div className="text-lg font-mono text-stellar-400">
              +{simulation.miss_distance_improvement_km.toFixed(3)} km ({simulation.miss_distance_improvement_percent.toFixed(1)}%)
            </div>
          </div>
          <div className="bg-slate-700/50 rounded p-3">
            <div className="text-xs text-slate-400 mb-1">ΔV / Fuel</div>
            <div className="text-lg font-mono text-white">
              {formatDeltaV(simulation.delta_v_magnitude)} / {simulation.fuel_consumption_kg?.toFixed(2) || '?'} kg
            </div>
          </div>
        </div>

        {/* Trajectory Preview */}
        {simulation.trajectory_points.length > 0 && (
          <div className="mb-4">
            <h4 className="text-sm font-medium text-slate-400 mb-2">Post-Burn Trajectory</h4>
            <div className="bg-slate-700/50 rounded p-3 max-h-40 overflow-y-auto">
              <table className="w-full text-xs font-mono">
                <thead className="text-slate-400">
                  <tr>
                    <th className="text-left py-1">Time</th>
                    <th className="text-right">Altitude</th>
                    <th className="text-right">X (km)</th>
                    <th className="text-right">Y (km)</th>
                    <th className="text-right">Z (km)</th>
                  </tr>
                </thead>
                <tbody className="text-slate-300">
                  {simulation.trajectory_points.map((point, i) => (
                    <tr key={i} className="border-t border-slate-600/50">
                      <td className="py-1">{new Date(point.timestamp).toLocaleTimeString()}</td>
                      <td className="text-right">{point.altitude_km.toFixed(1)}</td>
                      <td className="text-right">{point.position.x_km.toFixed(1)}</td>
                      <td className="text-right">{point.position.y_km.toFixed(1)}</td>
                      <td className="text-right">{point.position.z_km.toFixed(1)}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          </div>
        )}

        <button
          onClick={onClose}
          className="w-full py-2 bg-slate-600 hover:bg-slate-500 rounded text-slate-200 transition-colors"
        >
          Close
        </button>
      </div>
    </div>
  )
}
