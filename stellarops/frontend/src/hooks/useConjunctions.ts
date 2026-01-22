import { useState, useEffect, useCallback } from 'react'
import type { Conjunction, ConjunctionSeverity, ConjunctionStatus } from '../types'
import { api, type ConjunctionFilters } from '../services/api'
import { socketService } from '../services/socket'

/**
 * Hook for fetching and managing conjunction list
 */
export function useConjunctions(filters?: ConjunctionFilters) {
  const [conjunctions, setConjunctions] = useState<Conjunction[]>([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)

  const fetchData = useCallback(async () => {
    try {
      setLoading(true)
      setError(null)
      const data = await api.conjunctions.list(filters)
      setConjunctions(data)
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to fetch conjunctions')
    } finally {
      setLoading(false)
    }
  }, [filters])

  useEffect(() => {
    fetchData()
  }, [fetchData])

  // Subscribe to real-time updates
  useEffect(() => {
    const channel = socketService.joinChannel('conjunctions:updates')

    if (channel) {
      channel.on('conjunction_created', (payload: { conjunction: Conjunction }) => {
        setConjunctions(prev => [payload.conjunction, ...prev])
      })

      channel.on('conjunction_updated', (payload: { conjunction: Conjunction }) => {
        setConjunctions(prev =>
          prev.map(c => c.id === payload.conjunction.id ? payload.conjunction : c)
        )
      })

      channel.on('conjunction_expired', (payload: { id: string }) => {
        setConjunctions(prev =>
          prev.map(c => c.id === payload.id ? { ...c, status: 'expired' as ConjunctionStatus } : c)
        )
      })
    }

    return () => {
      socketService.leaveChannel('conjunctions:updates')
    }
  }, [])

  const refetch = useCallback(() => {
    fetchData()
  }, [fetchData])

  return { conjunctions, loading, error, refetch }
}

/**
 * Hook for fetching a single conjunction
 */
export function useConjunction(id: string | null) {
  const [conjunction, setConjunction] = useState<Conjunction | null>(null)
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState<string | null>(null)

  const fetchData = useCallback(async () => {
    if (!id) {
      setConjunction(null)
      return
    }

    try {
      setLoading(true)
      setError(null)
      const data = await api.conjunctions.get(id)
      setConjunction(data)
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to fetch conjunction')
    } finally {
      setLoading(false)
    }
  }, [id])

  useEffect(() => {
    fetchData()
  }, [fetchData])

  // Subscribe to updates for this specific conjunction
  useEffect(() => {
    if (!id) return

    const channel = socketService.joinChannel(`conjunction:${id}`)

    if (channel) {
      channel.on('updated', (payload: { conjunction: Conjunction }) => {
        setConjunction(payload.conjunction)
      })
    }

    return () => {
      socketService.leaveChannel(`conjunction:${id}`)
    }
  }, [id])

  const acknowledge = useCallback(async () => {
    if (!id) return
    try {
      const updated = await api.conjunctions.acknowledge(id)
      setConjunction(updated)
      return updated
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to acknowledge')
      throw err
    }
  }, [id])

  const resolve = useCallback(async () => {
    if (!id) return
    try {
      const updated = await api.conjunctions.resolve(id)
      setConjunction(updated)
      return updated
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to resolve')
      throw err
    }
  }, [id])

  return { conjunction, loading, error, refetch: fetchData, acknowledge, resolve }
}

/**
 * Utility to get severity color
 */
export function getSeverityColor(severity: ConjunctionSeverity): string {
  switch (severity) {
    case 'critical':
      return 'text-red-500 bg-red-500/10 border-red-500'
    case 'high':
      return 'text-orange-500 bg-orange-500/10 border-orange-500'
    case 'medium':
      return 'text-yellow-500 bg-yellow-500/10 border-yellow-500'
    case 'low':
      return 'text-green-500 bg-green-500/10 border-green-500'
    default:
      return 'text-slate-500 bg-slate-500/10 border-slate-500'
  }
}

/**
 * Utility to format TCA countdown
 */
export function formatTCACountdown(tca: string): string {
  const tcaDate = new Date(tca)
  const now = new Date()
  const diffMs = tcaDate.getTime() - now.getTime()

  if (diffMs <= 0) {
    return 'PASSED'
  }

  const hours = Math.floor(diffMs / (1000 * 60 * 60))
  const minutes = Math.floor((diffMs % (1000 * 60 * 60)) / (1000 * 60))
  const seconds = Math.floor((diffMs % (1000 * 60)) / 1000)

  if (hours >= 24) {
    const days = Math.floor(hours / 24)
    return `${days}d ${hours % 24}h`
  }

  return `${hours.toString().padStart(2, '0')}:${minutes.toString().padStart(2, '0')}:${seconds.toString().padStart(2, '0')}`
}
