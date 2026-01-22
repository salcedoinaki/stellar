import { create } from 'zustand'
import type { 
  SpaceObject, 
  Conjunction, 
  CourseOfAction,
  ConjunctionStatistics,
  DetectorStatus,
  ThreatLevel,
  ConjunctionSeverity 
} from '../types'
import { api } from '../services/api'

interface SSAState {
  // Space Objects
  spaceObjects: SpaceObject[]
  selectedSpaceObject: SpaceObject | null
  highThreatObjects: SpaceObject[]
  protectedAssets: SpaceObject[]
  
  // Conjunctions
  conjunctions: Conjunction[]
  criticalConjunctions: Conjunction[]
  selectedConjunction: Conjunction | null
  conjunctionStats: ConjunctionStatistics | null
  
  // COAs
  coas: CourseOfAction[]
  pendingCOAs: CourseOfAction[]
  selectedCOA: CourseOfAction | null
  
  // Detector
  detectorStatus: DetectorStatus | null
  
  // UI State
  isLoading: boolean
  error: string | null
  lastUpdated: Date | null
  
  // Actions - Space Objects
  fetchSpaceObjects: (filters?: Parameters<typeof api.spaceObjects.list>[0]) => Promise<void>
  fetchHighThreatObjects: () => Promise<void>
  fetchProtectedAssets: () => Promise<void>
  selectSpaceObject: (id: string | null) => void
  updateThreatAssessment: (id: string, assessment: { threat_level?: ThreatLevel; intel_summary?: string }) => Promise<void>
  
  // Actions - Conjunctions
  fetchConjunctions: (filters?: Parameters<typeof api.conjunctions.list>[0]) => Promise<void>
  fetchCriticalConjunctions: () => Promise<void>
  fetchConjunctionStats: () => Promise<void>
  selectConjunction: (id: string | null) => void
  
  // Actions - COAs
  fetchCOAs: (filters?: Parameters<typeof api.coa.list>[0]) => Promise<void>
  fetchPendingCOAs: () => Promise<void>
  selectCOA: (id: string | null) => void
  approveCOA: (id: string, approvedBy: string, notes?: string) => Promise<void>
  rejectCOA: (id: string, rejectedBy: string, notes?: string) => Promise<void>
  generateCOAs: (conjunctionId: string) => Promise<void>
  
  // Actions - Detector
  fetchDetectorStatus: () => Promise<void>
  triggerScreening: () => Promise<void>
  
  // Utility
  clearError: () => void
  refreshAll: () => Promise<void>
}

export const useSSAStore = create<SSAState>((set, get) => ({
  // Initial state
  spaceObjects: [],
  selectedSpaceObject: null,
  highThreatObjects: [],
  protectedAssets: [],
  conjunctions: [],
  criticalConjunctions: [],
  selectedConjunction: null,
  conjunctionStats: null,
  coas: [],
  pendingCOAs: [],
  selectedCOA: null,
  detectorStatus: null,
  isLoading: false,
  error: null,
  lastUpdated: null,

  // Space Objects Actions
  fetchSpaceObjects: async (filters) => {
    set({ isLoading: true, error: null })
    try {
      const spaceObjects = await api.spaceObjects.list(filters)
      set({ spaceObjects, lastUpdated: new Date() })
    } catch (error) {
      set({ error: error instanceof Error ? error.message : 'Failed to fetch space objects' })
    } finally {
      set({ isLoading: false })
    }
  },

  fetchHighThreatObjects: async () => {
    try {
      const highThreatObjects = await api.spaceObjects.highThreat()
      set({ highThreatObjects })
    } catch (error) {
      console.error('Failed to fetch high threat objects:', error)
    }
  },

  fetchProtectedAssets: async () => {
    try {
      const protectedAssets = await api.spaceObjects.protectedAssets()
      set({ protectedAssets })
    } catch (error) {
      console.error('Failed to fetch protected assets:', error)
    }
  },

  selectSpaceObject: (id) => {
    if (!id) {
      set({ selectedSpaceObject: null })
      return
    }
    const object = get().spaceObjects.find(o => o.id === id)
    set({ selectedSpaceObject: object || null })
  },

  updateThreatAssessment: async (id, assessment) => {
    try {
      const updated = await api.spaceObjects.updateThreat(id, assessment)
      set(state => ({
        spaceObjects: state.spaceObjects.map(o => o.id === id ? updated : o),
        selectedSpaceObject: state.selectedSpaceObject?.id === id ? updated : state.selectedSpaceObject,
        highThreatObjects: assessment.threat_level && ['high', 'critical'].includes(assessment.threat_level)
          ? [...state.highThreatObjects.filter(o => o.id !== id), updated]
          : state.highThreatObjects.filter(o => o.id !== id)
      }))
    } catch (error) {
      set({ error: error instanceof Error ? error.message : 'Failed to update threat assessment' })
    }
  },

  // Conjunction Actions
  fetchConjunctions: async (filters) => {
    set({ isLoading: true, error: null })
    try {
      const conjunctions = await api.conjunctions.list(filters)
      set({ conjunctions, lastUpdated: new Date() })
    } catch (error) {
      set({ error: error instanceof Error ? error.message : 'Failed to fetch conjunctions' })
    } finally {
      set({ isLoading: false })
    }
  },

  fetchCriticalConjunctions: async () => {
    try {
      const criticalConjunctions = await api.conjunctions.critical()
      set({ criticalConjunctions })
    } catch (error) {
      console.error('Failed to fetch critical conjunctions:', error)
    }
  },

  fetchConjunctionStats: async () => {
    try {
      const conjunctionStats = await api.conjunctions.statistics()
      set({ conjunctionStats })
    } catch (error) {
      console.error('Failed to fetch conjunction statistics:', error)
    }
  },

  selectConjunction: (id) => {
    if (!id) {
      set({ selectedConjunction: null })
      return
    }
    const conjunction = get().conjunctions.find(c => c.id === id) ||
                        get().criticalConjunctions.find(c => c.id === id)
    set({ selectedConjunction: conjunction || null })
  },

  // COA Actions
  fetchCOAs: async (filters) => {
    set({ isLoading: true, error: null })
    try {
      const coas = await api.coa.list(filters)
      set({ coas, lastUpdated: new Date() })
    } catch (error) {
      set({ error: error instanceof Error ? error.message : 'Failed to fetch COAs' })
    } finally {
      set({ isLoading: false })
    }
  },

  fetchPendingCOAs: async () => {
    try {
      const pendingCOAs = await api.coa.pending()
      set({ pendingCOAs })
    } catch (error) {
      console.error('Failed to fetch pending COAs:', error)
    }
  },

  selectCOA: (id) => {
    if (!id) {
      set({ selectedCOA: null })
      return
    }
    const coa = get().coas.find(c => c.id === id) ||
                get().pendingCOAs.find(c => c.id === id)
    set({ selectedCOA: coa || null })
  },

  approveCOA: async (id, approvedBy, notes) => {
    try {
      const updated = await api.coa.approve(id, approvedBy, notes)
      set(state => ({
        coas: state.coas.map(c => c.id === id ? updated : c),
        pendingCOAs: state.pendingCOAs.filter(c => c.id !== id),
        selectedCOA: state.selectedCOA?.id === id ? updated : state.selectedCOA
      }))
    } catch (error) {
      set({ error: error instanceof Error ? error.message : 'Failed to approve COA' })
    }
  },

  rejectCOA: async (id, rejectedBy, notes) => {
    try {
      const updated = await api.coa.reject(id, rejectedBy, notes)
      set(state => ({
        coas: state.coas.map(c => c.id === id ? updated : c),
        pendingCOAs: state.pendingCOAs.filter(c => c.id !== id),
        selectedCOA: state.selectedCOA?.id === id ? updated : state.selectedCOA
      }))
    } catch (error) {
      set({ error: error instanceof Error ? error.message : 'Failed to reject COA' })
    }
  },

  generateCOAs: async (conjunctionId) => {
    try {
      const newCOAs = await api.coa.generate(conjunctionId)
      set(state => ({
        coas: [...state.coas, ...newCOAs],
        pendingCOAs: [...state.pendingCOAs, ...newCOAs.filter(c => c.status === 'proposed')]
      }))
    } catch (error) {
      set({ error: error instanceof Error ? error.message : 'Failed to generate COAs' })
    }
  },

  // Detector Actions
  fetchDetectorStatus: async () => {
    try {
      const detectorStatus = await api.conjunctions.detectorStatus()
      set({ detectorStatus })
    } catch (error) {
      console.error('Failed to fetch detector status:', error)
    }
  },

  triggerScreening: async () => {
    try {
      await api.conjunctions.triggerScreening()
      // Refresh data after triggering
      setTimeout(() => {
        get().fetchCriticalConjunctions()
        get().fetchDetectorStatus()
      }, 5000)
    } catch (error) {
      set({ error: error instanceof Error ? error.message : 'Failed to trigger screening' })
    }
  },

  // Utility
  clearError: () => set({ error: null }),

  refreshAll: async () => {
    const { 
      fetchConjunctions, 
      fetchCriticalConjunctions, 
      fetchConjunctionStats,
      fetchPendingCOAs,
      fetchHighThreatObjects,
      fetchDetectorStatus 
    } = get()
    
    await Promise.all([
      fetchConjunctions({ upcoming: true, limit: 50 }),
      fetchCriticalConjunctions(),
      fetchConjunctionStats(),
      fetchPendingCOAs(),
      fetchHighThreatObjects(),
      fetchDetectorStatus()
    ])
  }
}))

// Selectors for common queries
export const selectThreatsByLevel = (state: SSAState) => {
  const counts: Record<ThreatLevel, number> = {
    none: 0,
    low: 0,
    medium: 0,
    high: 0,
    critical: 0
  }
  state.spaceObjects.forEach(obj => {
    counts[obj.threat_assessment.threat_level]++
  })
  return counts
}

export const selectConjunctionsBySeverity = (state: SSAState) => {
  const counts: Record<ConjunctionSeverity, number> = {
    low: 0,
    medium: 0,
    high: 0,
    critical: 0
  }
  state.conjunctions.forEach(conj => {
    counts[conj.severity]++
  })
  return counts
}

export const selectUpcomingConjunctions = (hours: number) => (state: SSAState) => {
  const cutoff = new Date(Date.now() + hours * 60 * 60 * 1000).toISOString()
  return state.conjunctions.filter(c => c.tca <= cutoff && c.status !== 'passed')
}

export default useSSAStore
