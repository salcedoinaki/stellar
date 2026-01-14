import { Link, useLocation } from 'react-router-dom'
import { useSatelliteStore } from '../store/satelliteStore'

interface LayoutProps {
  children: React.ReactNode
}

export default function Layout({ children }: LayoutProps) {
  const location = useLocation()
  const { satellites, isConnected } = useSatelliteStore()
  const satelliteCount = satellites.size

  const navLinks = [
    { path: '/', label: 'Dashboard', icon: '📊' },
    { path: '/satellites', label: 'Satellites', icon: '🛰️' },
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

            {/* Status indicators */}
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
