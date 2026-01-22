import { Link, useLocation } from 'react-router-dom'
import { useSatelliteStore } from '../store/satelliteStore'
import type { ConnectionState } from '../services/socket'

interface LayoutProps {
  children: React.ReactNode
  connectionState?: ConnectionState
  isConnected?: boolean
}

const connectionStateConfig: Record<ConnectionState, { color: string; label: string; animate?: boolean }> = {
  connected: { color: 'bg-green-500', label: 'Connected' },
  connecting: { color: 'bg-yellow-500', label: 'Connecting...', animate: true },
  reconnecting: { color: 'bg-orange-500', label: 'Reconnecting...', animate: true },
  disconnected: { color: 'bg-red-500', label: 'Disconnected' },
}

export default function Layout({ children, connectionState = 'disconnected', isConnected = false }: LayoutProps) {
  const location = useLocation()
  const { satellites } = useSatelliteStore()
  const satelliteCount = satellites.size
  
  const connectionConfig = connectionStateConfig[connectionState]

  const navLinks = [
    { path: '/', label: 'Dashboard', icon: '📊' },
    { path: '/satellites', label: 'Satellites', icon: '🛰️' },
    { path: '/map', label: 'Map', icon: '🗺️' },
  ]

  return (
    <div className="min-h-screen bg-slate-900 flex flex-col">
      {/* Connection warning banner */}
      {connectionState === 'reconnecting' && (
        <div className="bg-orange-600 text-white text-center py-2 text-sm">
          <span className="inline-flex items-center gap-2">
            <svg className="animate-spin h-4 w-4" viewBox="0 0 24 24">
              <circle className="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" strokeWidth="4" fill="none" />
              <path className="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z" />
            </svg>
            Reconnecting to server...
          </span>
        </div>
      )}
      
      {connectionState === 'disconnected' && (
        <div className="bg-red-600 text-white text-center py-2 text-sm">
          <span>Connection lost. Data may be stale.</span>
        </div>
      )}

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

            {/* Status indicators */}
            <div className="flex items-center gap-4">
              <div className="flex items-center gap-2 text-sm">
                <span className="text-slate-400">Satellites:</span>
                <span className="font-mono text-stellar-400">{satelliteCount}</span>
              </div>
              <div className="flex items-center gap-2">
                <div
                  className={`w-2 h-2 rounded-full ${connectionConfig.color} ${
                    connectionConfig.animate ? 'animate-pulse' : ''
                  }`}
                />
                <span className="text-xs text-slate-400">
                  {connectionConfig.label}
                </span>
              </div>
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
