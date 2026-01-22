import { useEffect, useCallback, useRef } from 'react'
import { socketService, ConnectionState } from '../services/socket'
import { useSatelliteStore } from '../store/satelliteStore'
import { api } from '../services/api'
import type { Satellite } from '../types'

/**
 * Hook to manage WebSocket connection lifecycle and satellite data synchronization.
 * 
 * Features:
 * - Automatic connection on mount
 * - Reconnection with exponential backoff
 * - Channel management for satellite updates
 * - Initial data fetch from REST API
 * - Telemetry history tracking
 */
export function useSocketConnection() {
  const { 
    setConnectionState, 
    setSatellites, 
    updateSatellite, 
    addTelemetry,
    connectionState,
    isConnected 
  } = useSatelliteStore()
  
  const mountedRef = useRef(true)
  const initialLoadDoneRef = useRef(false)

  // Fetch initial data from REST API
  const fetchInitialData = useCallback(async () => {
    if (initialLoadDoneRef.current) return
    
    try {
      const satellites = await api.getSatellites()
      if (mountedRef.current) {
        setSatellites(satellites)
        initialLoadDoneRef.current = true
      }
    } catch (error) {
      console.error('[useSocketConnection] Failed to fetch initial data:', error)
      // Retry after delay
      setTimeout(() => {
        if (mountedRef.current) {
          fetchInitialData()
        }
      }, 5000)
    }
  }, [setSatellites])

  // Handle incoming satellite updates
  const handleSatelliteUpdate = useCallback((payload: unknown) => {
    const data = payload as Partial<Satellite> & { id?: string; satellite_id?: string }
    const id = data.id || data.satellite_id
    
    if (id) {
      updateSatellite(id, data)
      
      // Add to telemetry history if it has telemetry data
      if (data.energy !== undefined || data.memory !== undefined) {
        addTelemetry(id, {
          energy: data.energy,
          memory: data.memory,
          temperature: data.temperature,
        })
      }
    }
  }, [updateSatellite, addTelemetry])

  // Handle connection state changes
  const handleConnectionChange = useCallback((state: ConnectionState) => {
    console.log('[useSocketConnection] Connection state:', state)
    setConnectionState(state)
    
    if (state === 'connected') {
      // Re-fetch data on reconnect to ensure consistency
      fetchInitialData()
    }
  }, [setConnectionState, fetchInitialData])

  // Setup socket connection
  useEffect(() => {
    mountedRef.current = true

    // Configure socket events
    socketService.setEvents({
      onConnectionChange: handleConnectionChange,
      onError: (error) => {
        console.error('[useSocketConnection] Socket error:', error)
      },
      onChannelError: (topic, error) => {
        console.error(`[useSocketConnection] Channel ${topic} error:`, error)
      },
    })

    // Connect to socket
    socketService.connect()

    // Fetch initial data
    fetchInitialData()

    // Cleanup on unmount
    return () => {
      mountedRef.current = false
      // Don't disconnect on unmount - let the socket persist for the app lifetime
    }
  }, [handleConnectionChange, fetchInitialData])

  // Join satellite channel when connected
  useEffect(() => {
    if (!isConnected) return

    const channel = socketService.joinChannel('satellites:lobby', {})
    
    if (channel) {
      // Listen for satellite updates
      const unsubUpdate = socketService.on('satellites:lobby', 'satellite:update', handleSatelliteUpdate)
      const unsubState = socketService.on('satellites:lobby', 'state_update', handleSatelliteUpdate)
      const unsubTelemetry = socketService.on('satellites:lobby', 'telemetry', (payload) => {
        const data = payload as { satellite_id: string; [key: string]: unknown }
        if (data.satellite_id) {
          addTelemetry(data.satellite_id, {
            energy: data.energy as number | undefined,
            memory: data.memory as number | undefined,
            temperature: data.temperature as number | undefined,
          })
        }
      })

      return () => {
        unsubUpdate()
        unsubState()
        unsubTelemetry()
      }
    }
  }, [isConnected, handleSatelliteUpdate, addTelemetry])

  return {
    connectionState,
    isConnected,
    reconnect: () => {
      socketService.disconnect()
      socketService.connect()
    },
  }
}

/**
 * Hook to subscribe to a specific satellite's channel.
 */
export function useSatelliteChannel(satelliteId: string | null) {
  const { updateSatellite, addTelemetry } = useSatelliteStore()
  const isConnected = useSatelliteStore((state) => state.isConnected)

  useEffect(() => {
    if (!isConnected || !satelliteId) return

    const topic = `satellite:${satelliteId}`
    const channel = socketService.joinChannel(topic, {})

    if (!channel) return

    const unsubState = socketService.on(topic, 'state_update', (payload) => {
      const data = payload as Partial<Satellite>
      updateSatellite(satelliteId, data)
    })

    const unsubTelemetry = socketService.on(topic, 'telemetry', (payload) => {
      const data = payload as { energy?: number; memory?: number; temperature?: number }
      addTelemetry(satelliteId, data)
    })

    const unsubCommand = socketService.on(topic, 'command_result', (payload) => {
      console.log(`[Satellite ${satelliteId}] Command result:`, payload)
    })

    return () => {
      unsubState()
      unsubTelemetry()
      unsubCommand()
      socketService.leaveChannel(topic)
    }
  }, [isConnected, satelliteId, updateSatellite, addTelemetry])

  // Return function to send commands
  const sendCommand = useCallback(async (command: string, params: object = {}) => {
    if (!satelliteId) {
      throw new Error('No satellite selected')
    }

    const topic = `satellite:${satelliteId}`
    return socketService.push(topic, 'command', { command, params })
  }, [satelliteId])

  return { sendCommand }
}

export default useSocketConnection
