import { Socket, Channel } from 'phoenix'

class SocketService {
  private socket: Socket | null = null
  private channels: Map<string, Channel> = new Map()

  connect(): void {
    if (this.socket) return

    const wsUrl = import.meta.env.VITE_WS_URL || 'ws://localhost:4000'
    
    this.socket = new Socket(`${wsUrl}/socket`, {
      params: { token: 'user-token' }, // In production, use proper auth tokens
      logger: (kind, msg, data) => {
        if (import.meta.env.DEV) {
          console.log(`[Socket ${kind}]`, msg, data)
        }
      },
    })

    this.socket.onOpen(() => {
      console.log('[Socket] Connected')
    })

    this.socket.onClose(() => {
      console.log('[Socket] Disconnected')
    })

    this.socket.onError((error) => {
      console.error('[Socket] Error:', error)
    })

    this.socket.connect()
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
