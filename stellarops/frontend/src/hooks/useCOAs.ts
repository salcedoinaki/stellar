import { useState, useEffect, useCallback } from 'react'
import type { COA, COASimulationResult, COAType, Mission } from '../types'
import { api } from '../services/api'
import { socketService } from '../services/socket'

/**
 * Hook for fetching COAs for a conjunction
 */
export function useCOAs(conjunctionId: string | null) {
  const [coas, setCoas] = useState<COA[]>([])
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState<string | null>(null)

  const fetchData = useCallback(async () => {
    if (!conjunctionId) {
      setCoas([])
      return
    }

    try {
      setLoading(true)
      setError(null)
      const data = await api.coas.listForConjunction(conjunctionId)
      // Sort by risk score (lowest first)
      const sorted = data.sort((a, b) => a.risk_score - b.risk_score)
      setCoas(sorted)
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to fetch COAs')
    } finally {
      setLoading(false)
    }
  }, [conjunctionId])

  useEffect(() => {
    fetchData()
  }, [fetchData])

  // Subscribe to real-time updates
  useEffect(() => {
    if (!conjunctionId) return

    const channel = socketService.joinChannel('coa:updates')

    if (channel) {
      channel.on('coa_selected', (payload: { coa_id: string }) => {
        setCoas(prev =>
          prev.map(c => ({
            ...c,
            status: c.id === payload.coa_id ? 'selected' : c.status === 'proposed' ? 'rejected' : c.status
          }))
        )
      })

      channel.on('coa_executing', (payload: { coa_id: string }) => {
        setCoas(prev =>
          prev.map(c => c.id === payload.coa_id ? { ...c, status: 'executing' } : c)
        )
      })

      channel.on('coa_completed', (payload: { coa_id: string }) => {
        setCoas(prev =>
          prev.map(c => c.id === payload.coa_id ? { ...c, status: 'completed' } : c)
        )
      })

      channel.on('coa_failed', (payload: { coa_id: string; reason: string }) => {
        setCoas(prev =>
          prev.map(c => c.id === payload.coa_id ? { ...c, status: 'failed', failure_reason: payload.reason } : c)
        )
      })
    }

    return () => {
      socketService.leaveChannel('coa:updates')
    }
  }, [conjunctionId])

  const refetch = useCallback(() => {
    fetchData()
  }, [fetchData])

  return { coas, loading, error, refetch }
}

/**
 * Hook for selecting a COA
 */
export function useSelectCOA() {
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState<string | null>(null)

  const selectCOA = useCallback(async (id: string, selectedBy?: string): Promise<{ coa: COA; missions: Mission[] } | null> => {
    try {
      setLoading(true)
      setError(null)
      const result = await api.coas.select(id, selectedBy)
      return { coa: result.data, missions: result.missions }
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to select COA')
      return null
    } finally {
      setLoading(false)
    }
  }, [])

  return { selectCOA, loading, error }
}

/**
 * Hook for simulating a COA
 */
export function useSimulateCOA() {
  const [simulation, setSimulation] = useState<COASimulationResult | null>(null)
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState<string | null>(null)

  const simulate = useCallback(async (id: string) => {
    try {
      setLoading(true)
      setError(null)
      const result = await api.coas.simulate(id)
      setSimulation(result)
      return result
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to simulate COA')
      return null
    } finally {
      setLoading(false)
    }
  }, [])

  const clearSimulation = useCallback(() => {
    setSimulation(null)
  }, [])

  return { simulation, loading, error, simulate, clearSimulation }
}

/**
 * Utility to get COA type display info
 */
export function getCOATypeInfo(type: COAType): { label: string; icon: string; color: string } {
  switch (type) {
    case 'retrograde_burn':
      return { label: 'Retrograde Burn', icon: '⬇️', color: 'text-blue-400' }
    case 'prograde_burn':
      return { label: 'Prograde Burn', icon: '⬆️', color: 'text-green-400' }
    case 'inclination_change':
      return { label: 'Inclination Change', icon: '↗️', color: 'text-purple-400' }
    case 'phasing':
      return { label: 'Phasing Maneuver', icon: '🔄', color: 'text-cyan-400' }
    case 'flyby':
      return { label: 'Defensive Flyby', icon: '🎯', color: 'text-red-400' }
    case 'station_keeping':
      return { label: 'Station Keeping', icon: '📍', color: 'text-yellow-400' }
    default:
      return { label: type, icon: '🛰️', color: 'text-slate-400' }
  }
}

/**
 * Utility to get risk score color
 */
export function getRiskScoreColor(score: number): string {
  if (score <= 25) return 'text-green-500 bg-green-500/10'
  if (score <= 50) return 'text-yellow-500 bg-yellow-500/10'
  if (score <= 75) return 'text-orange-500 bg-orange-500/10'
  return 'text-red-500 bg-red-500/10'
}

/**
 * Format delta-V for display
 */
export function formatDeltaV(deltaV: number): string {
  if (deltaV < 0.001) return '< 1 m/s'
  if (deltaV < 1) return `${(deltaV * 1000).toFixed(1)} m/s`
  return `${deltaV.toFixed(3)} km/s`
}
