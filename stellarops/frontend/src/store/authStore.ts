import { create } from 'zustand'
import { persist } from 'zustand/middleware'
import { socketService } from '../services/socket'

export interface User {
  id: string
  email: string
  name?: string
  role: 'admin' | 'operator' | 'analyst' | 'viewer'
  last_login_at?: string
}

interface AuthState {
  user: User | null
  accessToken: string | null
  refreshToken: string | null
  isAuthenticated: boolean
  isLoading: boolean
  error: string | null
  
  // Actions
  login: (email: string, password: string) => Promise<boolean>
  logout: () => Promise<void>
  refreshAccessToken: () => Promise<boolean>
  checkAuth: () => Promise<void>
  clearError: () => void
  
  // Permission checks
  hasRole: (role: User['role']) => boolean
  canPerform: (action: string) => boolean
}

const ROLE_HIERARCHY: Record<User['role'], number> = {
  admin: 4,
  operator: 3,
  analyst: 2,
  viewer: 1,
}

const ACTION_PERMISSIONS: Record<string, User['role'][]> = {
  view_dashboard: ['admin', 'operator', 'analyst', 'viewer'],
  view_satellites: ['admin', 'operator', 'analyst', 'viewer'],
  view_ssa: ['admin', 'operator', 'analyst'],
  approve_coa: ['admin', 'operator'],
  select_coa: ['admin', 'operator'],
  manage_missions: ['admin', 'operator'],
  create_mission: ['admin', 'operator'],
  acknowledge_alarm: ['admin', 'operator'],
  resolve_alarm: ['admin', 'operator'],
  classify_threat: ['admin', 'operator', 'analyst'],
  manage_users: ['admin'],
  manage_system: ['admin'],
}

const API_URL = import.meta.env.VITE_API_URL || 'http://localhost:4000'

export const useAuthStore = create<AuthState>()(
  persist(
    (set, get) => ({
      user: null,
      accessToken: null,
      refreshToken: null,
      isAuthenticated: false,
      isLoading: false,
      error: null,

      login: async (email: string, password: string): Promise<boolean> => {
        set({ isLoading: true, error: null })
        
        try {
          const response = await fetch(`${API_URL}/api/auth/login`, {
            method: 'POST',
            headers: {
              'Content-Type': 'application/json',
            },
            body: JSON.stringify({ email, password }),
          })

          const data = await response.json()

          if (!response.ok) {
            set({ 
              isLoading: false, 
              error: data.error?.message || data.error || 'Login failed' 
            })
            return false
          }

          const { access_token, refresh_token, token, user } = data
          const accessToken = access_token || token
          const refreshTokenValue = refresh_token || null

          // Store tokens
          localStorage.setItem('access_token', accessToken)
          if (refreshTokenValue) {
            localStorage.setItem('refresh_token', refreshTokenValue)
          }

          set({
            user,
            accessToken,
            refreshToken: refreshTokenValue,
            isAuthenticated: true,
            isLoading: false,
            error: null,
          })

          // Connect WebSocket with new token
          socketService.connect(accessToken)

          return true
        } catch (error) {
          set({ 
            isLoading: false, 
            error: 'Network error. Please try again.' 
          })
          return false
        }
      },

      logout: async (): Promise<void> => {
        const { accessToken } = get()
        
        try {
          if (accessToken) {
            await fetch(`${API_URL}/api/auth/logout`, {
              method: 'POST',
              headers: {
                'Authorization': `Bearer ${accessToken}`,
                'Content-Type': 'application/json',
              },
            })
          }
        } catch {
          // Ignore logout errors
        }

        // Clear tokens
        localStorage.removeItem('access_token')
        localStorage.removeItem('refresh_token')

        // Disconnect WebSocket
        socketService.disconnect()

        set({
          user: null,
          accessToken: null,
          refreshToken: null,
          isAuthenticated: false,
          error: null,
        })
      },

      refreshAccessToken: async (): Promise<boolean> => {
        const { accessToken, refreshToken } = get()
        const tokenToUse = refreshToken || accessToken
        
        if (!tokenToUse) return false

        try {
          const response = await fetch(`${API_URL}/api/auth/refresh`, {
            method: 'POST',
            headers: {
              'Authorization': `Bearer ${tokenToUse}`,
              'Content-Type': 'application/json',
            },
            body: refreshToken ? JSON.stringify({ refresh_token: refreshToken }) : undefined,
          })

          if (!response.ok) {
            // Token refresh failed, log out
            await get().logout()
            return false
          }

          const data = await response.json()
          const newAccessToken = data.access_token || data.token
          const newRefreshToken = data.refresh_token || null

          // Store new tokens
          localStorage.setItem('access_token', newAccessToken)
          if (newRefreshToken) {
            localStorage.setItem('refresh_token', newRefreshToken)
          }

          set({ 
            accessToken: newAccessToken,
            refreshToken: newRefreshToken,
            user: data.user || get().user,
          })

          // Update WebSocket token
          socketService.reconnect(newAccessToken)

          return true
        } catch {
          await get().logout()
          return false
        }
      },

      checkAuth: async (): Promise<void> => {
        const accessToken = localStorage.getItem('access_token')
        
        if (!accessToken) {
          set({ isAuthenticated: false, user: null })
          return
        }

        set({ isLoading: true })

        try {
          const response = await fetch(`${API_URL}/api/auth/me`, {
            headers: {
              'Authorization': `Bearer ${accessToken}`,
            },
          })

          if (!response.ok) {
            if (response.status === 401) {
              // Try to refresh token
              const refreshed = await get().refreshAccessToken()
              if (!refreshed) {
                set({ isAuthenticated: false, user: null, isLoading: false })
              }
            } else {
              set({ isLoading: false })
            }
            return
          }

          const data = await response.json()
          set({ 
            user: data.user, 
            accessToken,
            refreshToken: localStorage.getItem('refresh_token'),
            isAuthenticated: true,
            isLoading: false,
          })

          // Connect WebSocket
          socketService.connect(accessToken)
        } catch {
          set({ isLoading: false })
        }
      },

      clearError: () => set({ error: null }),

      hasRole: (requiredRole: User['role']): boolean => {
        const { user } = get()
        if (!user) return false
        return ROLE_HIERARCHY[user.role] >= ROLE_HIERARCHY[requiredRole]
      },

      canPerform: (action: string): boolean => {
        const { user } = get()
        if (!user) return false
        const allowedRoles = ACTION_PERMISSIONS[action]
        if (!allowedRoles) return false
        return allowedRoles.includes(user.role)
      },
    }),
    {
      name: 'stellar-auth',
      partialize: (state) => ({
        user: state.user,
        accessToken: state.accessToken,
        refreshToken: state.refreshToken,
        isAuthenticated: state.isAuthenticated,
      }),
    }
  )
)

// Helper hook to get auth headers
export function getAuthHeaders(): Record<string, string> {
  const token = useAuthStore.getState().accessToken
  if (!token) return {}
  return { 'Authorization': `Bearer ${token}` }
}

// Helper to check if user is authenticated
export function isAuthenticated(): boolean {
  return useAuthStore.getState().isAuthenticated
}

export default useAuthStore
