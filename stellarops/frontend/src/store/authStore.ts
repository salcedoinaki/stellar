import { create } from 'zustand';
import { persist } from 'zustand/middleware';
import { api } from '../services/api';

export interface User {
  id: string;
  email: string;
  name: string;
  role: 'admin' | 'operator' | 'analyst' | 'viewer';
  last_login_at?: string;
}

interface AuthState {
  user: User | null;
  token: string | null;
  isAuthenticated: boolean;
  isLoading: boolean;
  error: string | null;
  
  // Actions
  login: (email: string, password: string) => Promise<boolean>;
  logout: () => Promise<void>;
  refreshToken: () => Promise<boolean>;
  fetchCurrentUser: () => Promise<void>;
  clearError: () => void;
  
  // Helpers
  hasRole: (role: User['role']) => boolean;
  canPerform: (action: string) => boolean;
}

const roleHierarchy: Record<User['role'], number> = {
  admin: 4,
  operator: 3,
  analyst: 2,
  viewer: 1,
};

const actionPermissions: Record<string, User['role'][]> = {
  view_dashboard: ['admin', 'operator', 'analyst', 'viewer'],
  view_satellites: ['admin', 'operator', 'analyst', 'viewer'],
  view_ssa: ['admin', 'operator', 'analyst'],
  approve_coa: ['admin', 'operator'],
  manage_missions: ['admin', 'operator'],
  manage_users: ['admin'],
  manage_system: ['admin'],
};

export const useAuthStore = create<AuthState>()(
  persist(
    (set, get) => ({
      user: null,
      token: null,
      isAuthenticated: false,
      isLoading: false,
      error: null,

      login: async (email: string, password: string) => {
        set({ isLoading: true, error: null });
        
        try {
          const response = await fetch(`${import.meta.env.VITE_API_URL || 'http://localhost:4000'}/api/auth/login`, {
            method: 'POST',
            headers: {
              'Content-Type': 'application/json',
            },
            body: JSON.stringify({ email, password }),
          });

          const data = await response.json();

          if (!response.ok) {
            set({ 
              isLoading: false, 
              error: data.error || 'Login failed' 
            });
            return false;
          }

          set({
            user: data.user,
            token: data.token,
            isAuthenticated: true,
            isLoading: false,
            error: null,
          });

          return true;
        } catch (error) {
          set({ 
            isLoading: false, 
            error: 'Network error. Please try again.' 
          });
          return false;
        }
      },

      logout: async () => {
        const { token } = get();
        
        if (token) {
          try {
            await fetch(`${import.meta.env.VITE_API_URL || 'http://localhost:4000'}/api/auth/logout`, {
              method: 'POST',
              headers: {
                'Authorization': `Bearer ${token}`,
                'Content-Type': 'application/json',
              },
            });
          } catch (error) {
            // Ignore logout errors
          }
        }

        set({
          user: null,
          token: null,
          isAuthenticated: false,
          error: null,
        });
      },

      refreshToken: async () => {
        const { token } = get();
        
        if (!token) return false;

        try {
          const response = await fetch(`${import.meta.env.VITE_API_URL || 'http://localhost:4000'}/api/auth/refresh`, {
            method: 'POST',
            headers: {
              'Authorization': `Bearer ${token}`,
              'Content-Type': 'application/json',
            },
          });

          if (!response.ok) {
            // Token refresh failed, log out
            get().logout();
            return false;
          }

          const data = await response.json();
          set({ token: data.token });
          return true;
        } catch (error) {
          get().logout();
          return false;
        }
      },

      fetchCurrentUser: async () => {
        const { token } = get();
        
        if (!token) return;

        try {
          const response = await fetch(`${import.meta.env.VITE_API_URL || 'http://localhost:4000'}/api/auth/me`, {
            headers: {
              'Authorization': `Bearer ${token}`,
            },
          });

          if (!response.ok) {
            if (response.status === 401) {
              get().logout();
            }
            return;
          }

          const data = await response.json();
          set({ user: data.user, isAuthenticated: true });
        } catch (error) {
          // Network error, keep existing state
        }
      },

      clearError: () => set({ error: null }),

      hasRole: (requiredRole: User['role']) => {
        const { user } = get();
        if (!user) return false;
        return roleHierarchy[user.role] >= roleHierarchy[requiredRole];
      },

      canPerform: (action: string) => {
        const { user } = get();
        if (!user) return false;
        const allowedRoles = actionPermissions[action];
        if (!allowedRoles) return false;
        return allowedRoles.includes(user.role);
      },
    }),
    {
      name: 'stellar-auth',
      partialize: (state) => ({
        token: state.token,
        user: state.user,
        isAuthenticated: state.isAuthenticated,
      }),
    }
  )
);

// Helper hook to get auth headers
export function getAuthHeaders(): Record<string, string> {
  const token = useAuthStore.getState().token;
  if (!token) return {};
  return { 'Authorization': `Bearer ${token}` };
}

// Helper to check if user is authenticated
export function isAuthenticated(): boolean {
  return useAuthStore.getState().isAuthenticated;
}
