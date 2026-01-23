import { create } from 'zustand'
import { persist } from 'zustand/middleware'
import { api } from '../services/api'
import { socketService } from '../services/socket'

interface User {
  id: string
  email: string
  role: 'admin' | 'operator' | 'analyst' | 'viewer'
}

interface AuthState {
  user: User | null
  accessToken: string | null
  refreshToken: string | null
  isAuthenticated: boolean
  loading: boolean
  error: string | null
  
  // Actions
  login: (email: string, password: string) => Promise<boolean>
  logout: () => Promise<void>
  refreshAccessToken: () => Promise<boolean>
  checkAuth: () => Promise<void>
  clearError: () => void
  
  // Permission checks
  hasRole: (role: string) => boolean
  can: (permission: string) => boolean
}

const ROLE_HIERARCHY: Record<string, number> = {
  admin: 4,
  operator: 3,
  analyst: 2,
  viewer: 1,
}

const PERMISSION_ROLES: Record<string, string> = {
  manage_users: 'admin',
  select_coa: 'operator',
  create_mission: 'operator',
  classify_threat: 'analyst',
  view_dashboard: 'viewer',
  acknowledge_alarm: 'operator',
  resolve_alarm: 'operator',
}

export const useAuthStore = create<AuthState>()(
  persist(
    (set, get) => ({
      user: null,
      accessToken: null,
      refreshToken: null,
      isAuthenticated: false,
      loading: false,
      error: null,

      login: async (email: string, password: string): Promise<boolean> => {
        set({ loading: true, error: null })
        
        try {
          const response = await api.post('/auth/login', { email, password })
          const { access_token, refresh_token, user } = response.data
          
          // Store tokens
          localStorage.setItem('access_token', access_token)
          localStorage.setItem('refresh_token', refresh_token)
          
          // Update state
          set({
            user,
            accessToken: access_token,
            refreshToken: refresh_token,
            isAuthenticated: true,
            loading: false,
            error: null,
          })
          
          // Connect WebSocket with new token
          socketService.connect(access_token)
          
          return true
        } catch (error: any) {
          const message = error.response?.data?.error?.message || 'Login failed'
          set({ loading: false, error: message })
          return false
        }
      },

      logout: async (): Promise<void> => {
        const { accessToken } = get()
        
        try {
          if (accessToken) {
            await api.post('/auth/logout')
          }
        } catch {
          // Ignore logout errors
        }
        
        // Clear tokens
        localStorage.removeItem('access_token')
        localStorage.removeItem('refresh_token')
        
        // Disconnect WebSocket
        socketService.disconnect()
        
        // Clear state
        set({
          user: null,
          accessToken: null,
          refreshToken: null,
          isAuthenticated: false,
          loading: false,
          error: null,
        })
      },

      refreshAccessToken: async (): Promise<boolean> => {
        const { refreshToken } = get()
        
        if (!refreshToken) {
          return false
        }
        
        try {
          const response = await api.post('/auth/refresh', {
            refresh_token: refreshToken,
          })
          
          const { access_token, refresh_token: newRefreshToken, user } = response.data
          
          // Store new tokens
          localStorage.setItem('access_token', access_token)
          localStorage.setItem('refresh_token', newRefreshToken)
          
          // Update state
          set({
            user,
            accessToken: access_token,
            refreshToken: newRefreshToken,
            isAuthenticated: true,
          })
          
          // Update WebSocket token
          socketService.reconnect(access_token)
          
          return true
        } catch {
          // Refresh failed, logout
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
        
        set({ loading: true })
        
        try {
          const response = await api.get('/auth/me')
          const { user } = response.data
          
          set({
            user,
            accessToken,
            refreshToken: localStorage.getItem('refresh_token'),
            isAuthenticated: true,
            loading: false,
          })
          
          // Connect WebSocket
          socketService.connect(accessToken)
        } catch (error: any) {
          if (error.response?.status === 401) {
            // Try to refresh token
            const refreshed = await get().refreshAccessToken()
            if (!refreshed) {
              set({ isAuthenticated: false, user: null, loading: false })
            }
          } else {
            set({ loading: false })
          }
        }
      },

      clearError: () => set({ error: null }),

      hasRole: (requiredRole: string): boolean => {
        const { user } = get()
        if (!user) return false
        
        const userLevel = ROLE_HIERARCHY[user.role] || 0
        const requiredLevel = ROLE_HIERARCHY[requiredRole] || 0
        
        return userLevel >= requiredLevel
      },

      can: (permission: string): boolean => {
        const requiredRole = PERMISSION_ROLES[permission]
        if (!requiredRole) return false
        
        return get().hasRole(requiredRole)
      },
    }),
    {
      name: 'auth-storage',
      partialize: (state) => ({
        user: state.user,
        accessToken: state.accessToken,
        refreshToken: state.refreshToken,
        isAuthenticated: state.isAuthenticated,
      }),
    }
  )
)

// Setup API interceptor for token refresh
api.interceptors.response.use(
  (response) => response,
  async (error) => {
    const originalRequest = error.config
    
    if (error.response?.status === 401 && !originalRequest._retry) {
      originalRequest._retry = true
      
      const store = useAuthStore.getState()
      const refreshed = await store.refreshAccessToken()
      
      if (refreshed) {
        const newToken = store.accessToken
        originalRequest.headers.Authorization = `Bearer ${newToken}`
        return api(originalRequest)
      }
    }
    
    return Promise.reject(error)
  }
)

export default useAuthStore
