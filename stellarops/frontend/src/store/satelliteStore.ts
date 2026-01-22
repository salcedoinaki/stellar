import { create } from 'zustand'
import { devtools } from 'zustand/middleware'
import type { Satellite, TelemetryData, SatelliteMode } from '../types'
import type { ConnectionState } from '../services/socket'

interface SatelliteStoreState {
  // Satellite data
  satellites: Map<string, Satellite>
  selectedSatelliteId: string | null
  
  // Telemetry history (last N points per satellite)
  telemetryHistory: Map<string, TelemetryData[]>
  
  // Connection status
  isConnected: boolean
  connectionState: ConnectionState
  lastUpdate: Date | null
  reconnectAttempt: number
  
  // Actions
  setSatellites: (satellites: Satellite[]) => void
  updateSatellite: (id: string, updates: Partial<Satellite>) => void
  removeSatellite: (id: string) => void
  selectSatellite: (id: string | null) => void
  
  addTelemetry: (satelliteId: string, data: Partial<TelemetryData>) => void
  clearTelemetry: (satelliteId: string) => void
  
  setConnected: (connected: boolean) => void
  setConnectionState: (state: ConnectionState) => void
  setReconnectAttempt: (attempt: number) => void
  
  // Computed getters
  getSatellite: (id: string) => Satellite | undefined
  getSatellitesByMode: (mode: SatelliteMode) => Satellite[]
  getAverageEnergy: () => number
  getTelemetryHistory: (satelliteId: string) => TelemetryData[]
}

const MAX_TELEMETRY_POINTS = 100

export const useSatelliteStore = create<SatelliteStoreState>()(
  devtools(
    (set, get) => ({
      // Initial state
      satellites: new Map(),
      selectedSatelliteId: null,
      telemetryHistory: new Map(),
      isConnected: false,
      connectionState: 'disconnected' as ConnectionState,
      lastUpdate: null,
      reconnectAttempt: 0,

      // Actions
      setSatellites: (satellites) => {
        const satelliteMap = new Map<string, Satellite>()
        satellites.forEach((sat) => {
          satelliteMap.set(sat.id, sat)
        })
        set({ satellites: satelliteMap, lastUpdate: new Date() })
      },

      updateSatellite: (id, updates) => {
        set((state) => {
          const satellites = new Map(state.satellites)
          const existing = satellites.get(id)
          if (existing) {
            satellites.set(id, { ...existing, ...updates })
          } else {
            satellites.set(id, { id, mode: 'nominal', energy: 100, memory: 0, ...updates } as Satellite)
          }
          return { satellites, lastUpdate: new Date() }
        })
      },

      removeSatellite: (id) => {
        set((state) => {
          const satellites = new Map(state.satellites)
          satellites.delete(id)
          const telemetryHistory = new Map(state.telemetryHistory)
          telemetryHistory.delete(id)
          return { 
            satellites, 
            telemetryHistory,
            selectedSatelliteId: state.selectedSatelliteId === id ? null : state.selectedSatelliteId 
          }
        })
      },

      selectSatellite: (id) => {
        set({ selectedSatelliteId: id })
      },

      addTelemetry: (satelliteId, data) => {
        set((state) => {
          const telemetryHistory = new Map(state.telemetryHistory)
          const history = telemetryHistory.get(satelliteId) || []
          
          const newPoint: TelemetryData = {
            timestamp: Date.now(),
            energy: data.energy ?? 0,
            memory: data.memory ?? 0,
            temperature: data.temperature,
          }
          
          // Keep only last N points
          const updated = [...history, newPoint].slice(-MAX_TELEMETRY_POINTS)
          telemetryHistory.set(satelliteId, updated)
          
          return { telemetryHistory }
        })
      },

      clearTelemetry: (satelliteId) => {
        set((state) => {
          const telemetryHistory = new Map(state.telemetryHistory)
          telemetryHistory.delete(satelliteId)
          return { telemetryHistory }
        })
      },

      setConnected: (connected) => {
        set({ isConnected: connected })
      },

      setConnectionState: (state) => {
        set({ 
          connectionState: state, 
          isConnected: state === 'connected' 
        })
      },

      setReconnectAttempt: (attempt) => {
        set({ reconnectAttempt: attempt })
      },

      // Computed getters
      getSatellite: (id) => {
        return get().satellites.get(id)
      },

      getSatellitesByMode: (mode) => {
        const satellites = Array.from(get().satellites.values())
        return satellites.filter((sat) => sat.mode === mode)
      },

      getAverageEnergy: () => {
        const satellites = Array.from(get().satellites.values())
        if (satellites.length === 0) return 0
        const total = satellites.reduce((sum, sat) => sum + (sat.energy || 0), 0)
        return total / satellites.length
      },

      getTelemetryHistory: (satelliteId) => {
        return get().telemetryHistory.get(satelliteId) || []
      },
    }),
    { name: 'satellite-store' }
  )
)

export default useSatelliteStore
