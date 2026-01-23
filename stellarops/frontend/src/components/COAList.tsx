import type { COA } from '../types'
import COACard from './COACard'

interface COAListProps {
  conjunctionId: string
  coas: COA[]
  loading: boolean
  onRefetch: () => void
}

export default function COAList({ conjunctionId, coas, loading, onRefetch }: COAListProps) {
  const proposedCoas = coas.filter(c => c.status === 'proposed')
  const selectedCoa = coas.find(c => c.status === 'selected' || c.status === 'executing')
  const completedCoas = coas.filter(c => c.status === 'completed')
  const otherCoas = coas.filter(c => c.status === 'rejected' || c.status === 'failed')

  if (loading) {
    return (
      <div className="bg-slate-700/50 rounded-lg p-4">
        <h3 className="text-sm font-medium text-slate-400 mb-3">Course of Action Options</h3>
        <div className="text-center text-slate-400 py-8">Loading COA options...</div>
      </div>
    )
  }

  if (coas.length === 0) {
    return (
      <div className="bg-slate-700/50 rounded-lg p-4">
        <div className="flex items-center justify-between mb-3">
          <h3 className="text-sm font-medium text-slate-400">Course of Action Options</h3>
          <button
            onClick={onRefetch}
            className="text-xs text-stellar-400 hover:text-stellar-300"
          >
            Generate COAs
          </button>
        </div>
        <div className="text-center text-slate-400 py-8">
          No COA options available. Click "Generate COAs" to create options.
        </div>
      </div>
    )
  }

  return (
    <div className="bg-slate-700/50 rounded-lg p-4">
      <div className="flex items-center justify-between mb-4">
        <h3 className="text-sm font-medium text-slate-400">Course of Action Options</h3>
        <div className="flex items-center gap-2">
          <span className="text-xs text-slate-500">
            {proposedCoas.length} proposed, {selectedCoa ? '1 selected' : '0 selected'}
          </span>
          <button
            onClick={onRefetch}
            className="text-xs text-stellar-400 hover:text-stellar-300"
          >
            Regenerate
          </button>
        </div>
      </div>

      {/* Selected/Executing COA */}
      {selectedCoa && (
        <div className="mb-4">
          <h4 className="text-xs font-medium text-green-400 mb-2 uppercase">Active COA</h4>
          <COACard coa={selectedCoa} />
        </div>
      )}

      {/* Proposed COAs */}
      {proposedCoas.length > 0 && (
        <div className="mb-4">
          {selectedCoa && (
            <h4 className="text-xs font-medium text-slate-500 mb-2 uppercase">Other Options (Proposed)</h4>
          )}
          <div className="grid gap-3">
            {proposedCoas.map((coa, index) => (
              <COACard
                key={coa.id}
                coa={coa}
                isRecommended={index === 0 && !selectedCoa}
                onSelect={onRefetch}
              />
            ))}
          </div>
        </div>
      )}

      {/* Completed COAs */}
      {completedCoas.length > 0 && (
        <div className="mb-4">
          <h4 className="text-xs font-medium text-green-500 mb-2 uppercase">Completed</h4>
          <div className="grid gap-3">
            {completedCoas.map((coa) => (
              <COACard key={coa.id} coa={coa} />
            ))}
          </div>
        </div>
      )}

      {/* Rejected/Failed COAs */}
      {otherCoas.length > 0 && (
        <div>
          <h4 className="text-xs font-medium text-slate-500 mb-2 uppercase">Rejected/Failed</h4>
          <div className="grid gap-3">
            {otherCoas.map((coa) => (
              <COACard key={coa.id} coa={coa} />
            ))}
          </div>
        </div>
      )}
    </div>
  )
}
