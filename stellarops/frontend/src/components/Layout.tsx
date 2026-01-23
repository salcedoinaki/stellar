import { Link, useLocation, useNavigate } from 'react-router-dom'
import { useSatelliteStore } from '../store/satelliteStore'
import { useAuthStore } from '../store/authStore'
import { useState, useRef, useEffect } from 'react'

interface LayoutProps {
  children: React.ReactNode
}

export default function Layout({ children }: LayoutProps) {
  const location = useLocation()
  const navigate = useNavigate()
  const { satellites, isConnected } = useSatelliteStore()
  const { user, isAuthenticated, logout } = useAuthStore()
  const [showUserMenu, setShowUserMenu] = useState(false)
  const userMenuRef = useRef<HTMLDivElement>(null)
  const satelliteCount = satellites.size

  // Close menu when clicking outside
  useEffect(() => {
    const handleClickOutside = (event: MouseEvent) => {
      if (userMenuRef.current && !userMenuRef.current.contains(event.target as Node)) {
        setShowUserMenu(false)
      }
    }
    document.addEventListener('mousedown', handleClickOutside)
    return () => document.removeEventListener('mousedown', handleClickOutside)
  }, [])

  const handleLogout = async () => {
    await logout()
    navigate('/login')
  }

  const getRoleBadgeColor = (role: string) => {
    switch (role) {
      case 'admin': return 'bg-purple-600'
      case 'operator': return 'bg-blue-600'
      case 'analyst': return 'bg-green-600'
      default: return 'bg-slate-600'
    }
  }

export default function Layout({ children }: LayoutProps) {
  const location = useLocation()
  const { satellites, isConnected } = useSatelliteStore()
  const satelliteCount = satellites.size

  const navLinks = [
    { path: '/', label: 'Dashboard', icon: '📊' },
    { path: '/satellites', label: 'Satellites', icon: '🛰️' },
    { path: '/threats', label: 'Threats', icon: '⚠️' },
    { path: '/missions', label: 'Missions', icon: '📋' },
    { path: '/alarms', label: 'Alarms', icon: '🔔' },
    { path: '/orbital', label: 'Orbital', icon: '🌍' },
    { path: '/map', label: 'Map', icon: '🗺️' },
  ]

  return (
    <div className="min-h-screen bg-slate-900 flex flex-col">
      {/* Header */}
      <header className="bg-slate-800 border-b border-slate-700 sticky top-0 z-50">
        <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
          <div className="flex items-center justify-between h-16">
            {/* Logo */}
            <Link to="/" className="flex items-center gap-3">
              <img src="/satellite.svg" alt="StellarOps" className="h-8 w-8" />
              <span className="text-xl font-bold gradient-text">StellarOps</span>
            </Link>

            {/* Navigation */}
            <nav className="flex items-center gap-1">
              {navLinks.map((link) => (
                <Link
                  key={link.path}
                  to={link.path}
                  className={`px-4 py-2 rounded-lg text-sm font-medium transition-colors ${
                    location.pathname === link.path
                      ? 'bg-stellar-600 text-white'
                      : 'text-slate-300 hover:bg-slate-700 hover:text-white'
                  }`}
                >
                  <span className="mr-2">{link.icon}</span>
                  {link.label}
                </Link>
              ))}
            </nav>

            {/* Status indicators and User menu */}
            <div className="flex items-center gap-4">
              <div className="flex items-center gap-2 text-sm">
                <span className="text-slate-400">Satellites:</span>
                <span className="font-mono text-stellar-400">{satelliteCount}</span>
              </div>
              <div className="flex items-center gap-2">
                <div
                  className={`w-2 h-2 rounded-full ${
                    isConnected ? 'bg-green-500' : 'bg-red-500'
                  }`}
                />
                <span className="text-xs text-slate-400">
                  {isConnected ? 'Connected' : 'Disconnected'}
                </span>
              </div>
              
              {/* User Info */}
              {isAuthenticated && user ? (
                <div className="relative" ref={userMenuRef}>
                  <button
                    onClick={() => setShowUserMenu(!showUserMenu)}
                    className="flex items-center gap-2 px-3 py-2 rounded-lg hover:bg-slate-700 transition-colors"
                  >
                    <div className="w-8 h-8 rounded-full bg-stellar-600 flex items-center justify-center text-white font-medium">
                      {user.email.charAt(0).toUpperCase()}
                    </div>
                    <div className="text-left hidden md:block">
                      <div className="text-sm text-white">{user.email.split('@')[0]}</div>
                      <div className={`text-xs px-2 py-0.5 rounded ${getRoleBadgeColor(user.role)}`}>
                        {user.role}
                      </div>
                    </div>
                    <svg className="w-4 h-4 text-slate-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                      <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M19 9l-7 7-7-7" />
                    </svg>
                  </button>
                  
                  {/* Dropdown Menu */}
                  {showUserMenu && (
                    <div className="absolute right-0 mt-2 w-48 bg-slate-800 border border-slate-700 rounded-lg shadow-lg py-1 z-50">
                      <div className="px-4 py-2 border-b border-slate-700">
                        <div className="text-sm text-white">{user.email}</div>
                        <div className="text-xs text-slate-400">Role: {user.role}</div>
                      </div>
                      <Link
                        to="/profile"
                        className="block px-4 py-2 text-sm text-slate-300 hover:bg-slate-700"
                        onClick={() => setShowUserMenu(false)}
                      >
                        Profile Settings
                      </Link>
                      <button
                        onClick={handleLogout}
                        className="block w-full text-left px-4 py-2 text-sm text-red-400 hover:bg-slate-700"
                      >
                        Sign Out
                      </button>
                    </div>
                  )}
                </div>
              ) : (
                <Link
                  to="/login"
                  className="px-4 py-2 bg-stellar-600 text-white rounded-lg text-sm font-medium hover:bg-stellar-500 transition-colors"
                >
                  Sign In
                </Link>
              )}
            </div>
          </div>
        </div>
      </header>

      {/* Main content */}
      <main className="flex-1">
        <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-6">
          {children}
        </div>
      </main>

      {/* Footer */}
      <footer className="bg-slate-800 border-t border-slate-700 py-4">
        <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
          <div className="flex items-center justify-between text-sm text-slate-400">
            <span>StellarOps Mission Control v0.1.0</span>
            <span>
              Last update:{' '}
              <span className="text-slate-300">
                {new Date().toLocaleTimeString()}
              </span>
            </span>
          </div>
        </div>
      </footer>
    </div>
  )
}
