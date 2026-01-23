import { Socket, Channel } from 'phoenix'

// Get auth token from localStorage or auth store
const getAuthToken = (): string | null => {
  // Try localStorage first
  const token = localStorage.getItem('access_token')
  if (token) return token
  
  // Try sessionStorage as fallback
  return sessionStorage.getItem('access_token')
}

class SocketService {
  private socket: Socket | null = null
  private channels: Map<string, Channel> = new Map()
  private reconnectAttempts = 0
  private maxReconnectAttempts = 5

  connect(token?: string): void {
    if (this.socket?.isConnected()) return

    const wsUrl = import.meta.env.VITE_WS_URL || 'ws://localhost:4000'
    const authToken = token || getAuthToken()
    
    if (!authToken) {
      console.warn('[Socket] No auth token available. Connection may fail for protected channels.')
    }
    
    this.socket = new Socket(`${wsUrl}/socket`, {
      params: { token: authToken },
      logger: (kind, msg, data) => {
        if (import.meta.env.DEV) {
          console.log(`[Socket ${kind}]`, msg, data)
        }
      },
      reconnectAfterMs: (tries) => {
        // Exponential backoff: 1s, 2s, 4s, 8s, 16s, then cap at 30s
        return Math.min(1000 * Math.pow(2, tries), 30000)
      },
    })

    this.socket.onOpen(() => {
      console.log('[Socket] Connected')
      this.reconnectAttempts = 0
    })

    this.socket.onClose(() => {
      console.log('[Socket] Disconnected')
    })

    this.socket.onError((error) => {
      console.error('[Socket] Error:', error)
      this.reconnectAttempts++
      
      if (this.reconnectAttempts >= this.maxReconnectAttempts) {
        console.error('[Socket] Max reconnect attempts reached')
      }
    })

    this.socket.connect()
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
    this.channels.forEach((channel) => {
      channel.leave()
    })
    this.channels.clear()

    if (this.socket) {
      this.socket.disconnect()
      this.socket = null
    }
  }

  joinChannel(topic: string, params: object = {}): Channel | null {
    if (!this.socket) {
      console.warn('[Socket] Not connected. Call connect() first.')
      return null
    }

    // Return existing channel if already joined
    if (this.channels.has(topic)) {
      return this.channels.get(topic) || null
    }

    const channel = this.socket.channel(topic, params)

    channel
      .join()
      .receive('ok', (resp) => {
        console.log(`[Channel] Joined ${topic}:`, resp)
      })
      .receive('error', (resp) => {
        console.error(`[Channel] Failed to join ${topic}:`, resp)
      })
      .receive('timeout', () => {
        console.warn(`[Channel] Timeout joining ${topic}`)
      })

    this.channels.set(topic, channel)
    return channel
  }

  leaveChannel(topic: string): void {
    const channel = this.channels.get(topic)
    if (channel) {
      channel.leave()
      this.channels.delete(topic)
    }
  }

  getChannel(topic: string): Channel | null {
    return this.channels.get(topic) || null
  }

  push(topic: string, event: string, payload: object = {}): void {
    const channel = this.channels.get(topic)
    if (channel) {
      channel.push(event, payload)
    } else {
      console.warn(`[Socket] Channel ${topic} not found`)
    }
  }

  isConnected(): boolean {
    return this.socket?.isConnected() ?? false
  }
}

// Singleton instance
export const socketService = new SocketService()

export default socketService
