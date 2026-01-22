import { useEffect, useCallback, useRef } from 'react'
import { socketService } from '../services/socket'
import { useSatelliteStore } from '../store/satelliteStore'
import { useSSAStore } from '../store/ssaStore'
import type { 
  Conjunction, 
  CourseOfAction, 
  SpaceObject, 
  DetectorStatus,
  ConjunctionStatistics 
} from '../types'

interface SSAChannelEvents {
  onConjunctionDetected?: (conjunction: Conjunction) => void
  onCOAGenerated?: (coas: CourseOfAction[]) => void
  onCOAApproved?: (coa: CourseOfAction) => void
  onCOAExecuting?: (coa: CourseOfAction) => void
  onThreatUpdated?: (object: SpaceObject) => void
  onScreeningComplete?: (results: { found: number; screened: number }) => void
}

/**
 * Hook to manage SSA WebSocket channel and real-time updates.
 * 
 * Features:
 * - Automatic subscription to SSA events
 * - Real-time conjunction detection updates
 * - COA status change notifications
 * - Threat assessment updates
 * - Integration with SSA Zustand store
 */
export function useSSAChannel(events?: SSAChannelEvents) {
  const { isConnected } = useSatelliteStore()
  const {
    setCriticalConjunctions,
    setConjunctionStats,
    setDetectorStatus,
    setPendingCOAs,
    setHighThreatObjects,
    addConjunction,
    updateConjunction,
    addCOA,
    updateCOA,
    updateSpaceObject,
  } = useSSAStore()

  const mountedRef = useRef(true)
  const channelJoinedRef = useRef(false)

  // Handle initial data on channel join
  const handleCriticalConjunctions = useCallback((payload: { conjunctions: Conjunction[]; count: number }) => {
    if (!mountedRef.current) return
    setCriticalConjunctions(payload.conjunctions)
  }, [setCriticalConjunctions])

  const handleConjunctionStats = useCallback((stats: ConjunctionStatistics) => {
    if (!mountedRef.current) return
    setConjunctionStats(stats)
  }, [setConjunctionStats])

  const handleDetectorStatus = useCallback((status: DetectorStatus) => {
    if (!mountedRef.current) return
    setDetectorStatus(status)
  }, [setDetectorStatus])

  const handlePendingCOAs = useCallback((payload: { coas: CourseOfAction[]; count: number }) => {
    if (!mountedRef.current) return
    setPendingCOAs(payload.coas)
  }, [setPendingCOAs])

  const handleHighThreatObjects = useCallback((payload: { objects: SpaceObject[]; count: number }) => {
    if (!mountedRef.current) return
    setHighThreatObjects(payload.objects)
  }, [setHighThreatObjects])

  // Handle real-time events
  const handleConjunctionDetected = useCallback((conjunction: Conjunction) => {
    if (!mountedRef.current) return
    addConjunction(conjunction)
    events?.onConjunctionDetected?.(conjunction)
  }, [addConjunction, events])

  const handleConjunctionUpdated = useCallback((conjunction: Conjunction) => {
    if (!mountedRef.current) return
    updateConjunction(conjunction.id, conjunction)
  }, [updateConjunction])

  const handleCOAGenerated = useCallback((payload: { coas: CourseOfAction[]; count: number } | CourseOfAction) => {
    if (!mountedRef.current) return
    
    if ('coas' in payload) {
      payload.coas.forEach(coa => addCOA(coa))
      events?.onCOAGenerated?.(payload.coas)
    } else {
      addCOA(payload)
      events?.onCOAGenerated?.([payload])
    }
  }, [addCOA, events])

  const handleCOAApproved = useCallback((coa: CourseOfAction) => {
    if (!mountedRef.current) return
    updateCOA(coa.id, coa)
    events?.onCOAApproved?.(coa)
  }, [updateCOA, events])

  const handleCOARejected = useCallback((coa: CourseOfAction) => {
    if (!mountedRef.current) return
    updateCOA(coa.id, coa)
  }, [updateCOA])

  const handleCOAExecuting = useCallback((coa: CourseOfAction) => {
    if (!mountedRef.current) return
    updateCOA(coa.id, coa)
    events?.onCOAExecuting?.(coa)
  }, [updateCOA, events])

  const handleThreatUpdated = useCallback((object: SpaceObject) => {
    if (!mountedRef.current) return
    updateSpaceObject(object.id, object)
    events?.onThreatUpdated?.(object)
  }, [updateSpaceObject, events])

  const handleScreeningStarted = useCallback((info: { timestamp: string }) => {
    if (!mountedRef.current) return
    console.log('[SSA] Screening started:', info)
  }, [])

  const handleScreeningComplete = useCallback((results: { found: number; screened: number }) => {
    if (!mountedRef.current) return
    console.log('[SSA] Screening complete:', results)
    events?.onScreeningComplete?.(results)
  }, [events])

  // Join SSA channels when connected
  useEffect(() => {
    mountedRef.current = true

    if (!isConnected) {
      channelJoinedRef.current = false
      return
    }

    if (channelJoinedRef.current) return

    // Join the all-in-one SSA channel
    const channel = socketService.joinChannel('ssa:all', {})
    
    if (channel) {
      channelJoinedRef.current = true

      // Initial data handlers
      const unsubCritical = socketService.on('ssa:all', 'critical_conjunctions', handleCriticalConjunctions)
      const unsubStats = socketService.on('ssa:all', 'conjunction_stats', handleConjunctionStats)
      const unsubDetector = socketService.on('ssa:all', 'detector_status', handleDetectorStatus)
      const unsubPending = socketService.on('ssa:all', 'pending_coas', handlePendingCOAs)
      const unsubThreats = socketService.on('ssa:all', 'high_threat_objects', handleHighThreatObjects)
      const unsubSummary = socketService.on('ssa:all', 'ssa_summary', (summary: {
        critical_conjunctions: number
        pending_coas: number
        high_threat_objects: number
        conjunction_stats: ConjunctionStatistics
        detector_status: DetectorStatus
      }) => {
        if (!mountedRef.current) return
        setConjunctionStats(summary.conjunction_stats)
        setDetectorStatus(summary.detector_status)
      })

      // Real-time event handlers
      const unsubDetected = socketService.on('ssa:all', 'conjunction_detected', handleConjunctionDetected)
      const unsubUpdated = socketService.on('ssa:all', 'conjunction_updated', handleConjunctionUpdated)
      const unsubCOAGenerated = socketService.on('ssa:all', 'coa_generated', handleCOAGenerated)
      const unsubCOAApproved = socketService.on('ssa:all', 'coa_approved', handleCOAApproved)
      const unsubCOARejected = socketService.on('ssa:all', 'coa_rejected', handleCOARejected)
      const unsubCOAExecuting = socketService.on('ssa:all', 'coa_executing', handleCOAExecuting)
      const unsubThreatUpdated = socketService.on('ssa:all', 'threat_updated', handleThreatUpdated)
      const unsubScreeningStarted = socketService.on('ssa:all', 'screening_started', handleScreeningStarted)
      const unsubScreeningComplete = socketService.on('ssa:all', 'screening_complete', handleScreeningComplete)

      return () => {
        unsubCritical()
        unsubStats()
        unsubDetector()
        unsubPending()
        unsubThreats()
        unsubSummary()
        unsubDetected()
        unsubUpdated()
        unsubCOAGenerated()
        unsubCOAApproved()
        unsubCOARejected()
        unsubCOAExecuting()
        unsubThreatUpdated()
        unsubScreeningStarted()
        unsubScreeningComplete()
        socketService.leaveChannel('ssa:all')
        channelJoinedRef.current = false
      }
    }
  }, [
    isConnected,
    handleCriticalConjunctions,
    handleConjunctionStats,
    handleDetectorStatus,
    handlePendingCOAs,
    handleHighThreatObjects,
    handleConjunctionDetected,
    handleConjunctionUpdated,
    handleCOAGenerated,
    handleCOAApproved,
    handleCOARejected,
    handleCOAExecuting,
    handleThreatUpdated,
    handleScreeningStarted,
    handleScreeningComplete,
    setConjunctionStats,
    setDetectorStatus,
  ])

  // Cleanup on unmount
  useEffect(() => {
    return () => {
      mountedRef.current = false
    }
  }, [])

  // Actions that can be called via WebSocket
  const triggerScreening = useCallback(async () => {
    try {
      const result = await socketService.push('ssa:all', 'trigger_screening', {})
      return result
    } catch (error) {
      console.error('[SSA] Failed to trigger screening:', error)
      throw error
    }
  }, [])

  const approveCOA = useCallback(async (id: string, userId: string, notes?: string) => {
    try {
      const result = await socketService.push('ssa:all', 'approve_coa', { 
        id, 
        user_id: userId, 
        notes: notes || '' 
      })
      return result
    } catch (error) {
      console.error('[SSA] Failed to approve COA:', error)
      throw error
    }
  }, [])

  const rejectCOA = useCallback(async (id: string, userId: string, notes?: string) => {
    try {
      const result = await socketService.push('ssa:all', 'reject_coa', { 
        id, 
        user_id: userId, 
        notes: notes || '' 
      })
      return result
    } catch (error) {
      console.error('[SSA] Failed to reject COA:', error)
      throw error
    }
  }, [])

  const generateCOAs = useCallback(async (conjunctionId: string) => {
    try {
      const result = await socketService.push('ssa:all', 'generate_coas', { 
        conjunction_id: conjunctionId 
      })
      return result
    } catch (error) {
      console.error('[SSA] Failed to generate COAs:', error)
      throw error
    }
  }, [])

  return {
    triggerScreening,
    approveCOA,
    rejectCOA,
    generateCOAs,
  }
}

/**
 * Hook to subscribe to a specific satellite's SSA events.
 */
export function useSatelliteSSAChannel(satelliteId: string | null) {
  const { isConnected } = useSatelliteStore()
  const { addConjunction, addCOA } = useSSAStore()

  useEffect(() => {
    if (!isConnected || !satelliteId) return

    const topic = `ssa:satellite:${satelliteId}`
    const channel = socketService.joinChannel(topic, {})

    if (!channel) return

    const unsubConjunction = socketService.on(topic, 'conjunction_detected', (payload: Conjunction) => {
      addConjunction(payload)
    })

    const unsubCOA = socketService.on(topic, 'coa_generated', (payload: CourseOfAction) => {
      addCOA(payload)
    })

    return () => {
      unsubConjunction()
      unsubCOA()
      socketService.leaveChannel(topic)
    }
  }, [isConnected, satelliteId, addConjunction, addCOA])
}

export default useSSAChannel
