import { Socket, Channel } from 'phoenix'

export type ConnectionState = 'disconnected' | 'connecting' | 'connected' | 'reconnecting'

export interface SocketEvents {
  onConnectionChange?: (state: ConnectionState) => void
  onError?: (error: unknown) => void
  onChannelError?: (topic: string, error: unknown) => void
}

// Get auth token from localStorage or auth store
const getAuthToken = (): string | null => {
  // Try localStorage first (access_token for new auth, auth_token for legacy)
  const accessToken = localStorage.getItem('access_token')
  if (accessToken) return accessToken
  
  const authToken = localStorage.getItem('auth_token')
  if (authToken) return authToken
  
  // Try sessionStorage as fallback
  return sessionStorage.getItem('access_token')
}

class SocketService {
  private socket: Socket | null = null
  private channels: Map<string, Channel> = new Map()
  private channelListeners: Map<string, Map<string, (payload: unknown) => void>> = new Map()
  private connectionState: ConnectionState = 'disconnected'
  private reconnectAttempts: number = 0
  private maxReconnectAttempts: number = 10
  private baseReconnectDelay: number = 1000
  private maxReconnectDelay: number = 30000
  private events: SocketEvents = {}
  private reconnectTimer: ReturnType<typeof setTimeout> | null = null
  private pendingChannels: Array<{ topic: string; params: object }> = []

  setEvents(events: SocketEvents): void {
    this.events = events
  }

  getConnectionState(): ConnectionState {
    return this.connectionState
  }

  private setConnectionState(state: ConnectionState): void {
    if (this.connectionState !== state) {
      this.connectionState = state
      this.events.onConnectionChange?.(state)
    }
  }

  connect(token?: string): void {
    if (this.socket?.isConnected()) {
      return
    }

    // Clear any pending reconnect
    if (this.reconnectTimer) {
      clearTimeout(this.reconnectTimer)
      this.reconnectTimer = null
    }

    this.setConnectionState('connecting')

    const wsUrl = import.meta.env.VITE_WS_URL || 'ws://localhost:4000'
    const authToken = token || getAuthToken()
    
    if (!authToken) {
      console.warn('[Socket] No auth token available. Connection may fail for protected channels.')
    }
    
    this.socket = new Socket(`${wsUrl}/socket`, {
      params: { token: authToken || 'guest-token' },
      reconnectAfterMs: (tries: number) => {
        // Custom reconnect backoff with jitter
        const delay = Math.min(
          this.baseReconnectDelay * Math.pow(2, tries) + Math.random() * 1000,
          this.maxReconnectDelay
        )
        return delay
      },
      logger: (kind, msg, data) => {
        if (import.meta.env.DEV) {
          console.log(`[Socket ${kind}]`, msg, data)
        }
      },
      heartbeatIntervalMs: 30000,
      timeout: 10000,
    })

    this.socket.onOpen(() => {
      console.log('[Socket] Connected')
      this.setConnectionState('connected')
      this.reconnectAttempts = 0
      
      // Rejoin any channels that were pending
      this.rejoinPendingChannels()
    })

    this.socket.onClose((event) => {
      console.log('[Socket] Disconnected', event)
      
      if (this.connectionState === 'connected') {
        this.setConnectionState('reconnecting')
        this.scheduleReconnect()
      }
    })

    this.socket.onError((error) => {
      console.error('[Socket] Error:', error)
      this.events.onError?.(error)
      
      if (this.connectionState === 'connecting') {
        this.scheduleReconnect()
      }
    })

    this.socket.connect()
  }

  private scheduleReconnect(): void {
    if (this.reconnectAttempts >= this.maxReconnectAttempts) {
      console.error('[Socket] Max reconnect attempts reached')
      this.setConnectionState('disconnected')
      return
    }

    this.reconnectAttempts++
    this.setConnectionState('reconnecting')

    const delay = Math.min(
      this.baseReconnectDelay * Math.pow(2, this.reconnectAttempts - 1),
      this.maxReconnectDelay
    )

    console.log(`[Socket] Reconnecting in ${delay}ms (attempt ${this.reconnectAttempts})`)

    this.reconnectTimer = setTimeout(() => {
      this.reconnectTimer = null
      this.socket?.connect()
    }, delay)
  }

  private rejoinPendingChannels(): void {
    // Re-join channels that were joined before disconnect
    const currentChannels = Array.from(this.channels.entries())
    
    currentChannels.forEach(([topic, channel]) => {
      if (channel.state !== 'joined') {
        console.log(`[Socket] Rejoining channel: ${topic}`)
        channel.rejoin()
      }
    })

    // Join any pending channels
    const pending = [...this.pendingChannels]
    this.pendingChannels = []
    
    pending.forEach(({ topic, params }) => {
      this.joinChannel(topic, params)
    })
  }

  // Reconnect with a new token (e.g., after token refresh)
  reconnect(newToken: string): void {
    this.disconnect()
    this.connect(newToken)
  }

  // Update token without full reconnect
  updateToken(newToken: string): void {
    if (this.socket) {
      // Store new token for next connection
      localStorage.setItem('access_token', newToken)
    }
  }

  disconnect(): void {
    if (this.reconnectTimer) {
      clearTimeout(this.reconnectTimer)
      this.reconnectTimer = null
    }

    this.channels.forEach((channel, topic) => {
      channel.leave()
      this.channelListeners.delete(topic)
    })
    this.channels.clear()
    this.pendingChannels = []

    if (this.socket) {
      this.socket.disconnect()
      this.socket = null
    }

    this.setConnectionState('disconnected')
    this.reconnectAttempts = 0
  }

  joinChannel(topic: string, params: object = {}): Channel | null {
    if (!this.socket) {
      console.warn('[Socket] Not connected. Queueing channel join.')
      this.pendingChannels.push({ topic, params })
      return null
    }

    // Return existing channel if already joined
    const existing = this.channels.get(topic)
    if (existing && existing.state === 'joined') {
      return existing
    }

    const channel = this.socket.channel(topic, params)

    channel
      .join()
      .receive('ok', (resp) => {
        console.log(`[Channel] Joined ${topic}:`, resp)
      })
      .receive('error', (resp) => {
        console.error(`[Channel] Failed to join ${topic}:`, resp)
        this.events.onChannelError?.(topic, resp)
        
        // Retry join after delay if socket is connected
        if (this.socket?.isConnected()) {
          setTimeout(() => {
            if (this.channels.has(topic)) {
              console.log(`[Channel] Retrying join for ${topic}`)
              channel.rejoin()
            }
          }, 5000)
        }
      })
      .receive('timeout', () => {
        console.warn(`[Channel] Timeout joining ${topic}`)
        
        // Retry on timeout
        if (this.socket?.isConnected()) {
          setTimeout(() => {
            if (this.channels.has(topic)) {
              channel.rejoin()
            }
          }, 3000)
        }
      })

    // Handle channel-level errors
    channel.onError((error) => {
      console.error(`[Channel] Error on ${topic}:`, error)
      this.events.onChannelError?.(topic, error)
    })

    // Handle channel close
    channel.onClose(() => {
      console.log(`[Channel] Closed ${topic}`)
      
      // Rejoin if socket is still connected
      if (this.socket?.isConnected() && this.channels.has(topic)) {
        console.log(`[Channel] Auto-rejoining ${topic}`)
        channel.rejoin()
      }
    })

    this.channels.set(topic, channel)
    return channel
  }

  leaveChannel(topic: string): void {
    const channel = this.channels.get(topic)
    if (channel) {
      channel.leave()
      this.channels.delete(topic)
      this.channelListeners.delete(topic)
    }
  }

  getChannel(topic: string): Channel | null {
    return this.channels.get(topic) || null
  }

  on(topic: string, event: string, callback: (payload: unknown) => void): () => void {
    const channel = this.channels.get(topic)
    if (!channel) {
      console.warn(`[Socket] Channel ${topic} not found for event ${event}`)
      return () => {}
    }

    // Store listener for potential re-registration
    if (!this.channelListeners.has(topic)) {
      this.channelListeners.set(topic, new Map())
    }
    this.channelListeners.get(topic)?.set(event, callback)

    // Register with Phoenix channel
    const ref = channel.on(event, callback)

    // Return unsubscribe function
    return () => {
      channel.off(event, ref)
      this.channelListeners.get(topic)?.delete(event)
    }
  }

  push(topic: string, event: string, payload: object = {}): Promise<unknown> {
    return new Promise((resolve, reject) => {
      const channel = this.channels.get(topic)
      if (!channel) {
        reject(new Error(`Channel ${topic} not found`))
        return
      }

      if (channel.state !== 'joined') {
        reject(new Error(`Channel ${topic} not in joined state`))
        return
      }

      channel
        .push(event, payload)
        .receive('ok', resolve)
        .receive('error', reject)
        .receive('timeout', () => reject(new Error('Push timeout')))
    })
  }

  isConnected(): boolean {
    return this.socket?.isConnected() ?? false
  }

  // Get all joined channel topics
  getJoinedChannels(): string[] {
    return Array.from(this.channels.keys()).filter(
      (topic) => this.channels.get(topic)?.state === 'joined'
    )
  }
}

// Singleton instance
export const socketService = new SocketService()

export default socketService
