import { Routes, Route } from 'react-router-dom'
import Layout from './components/Layout'
import { PageErrorBoundary } from './components/ErrorBoundary'
import ChatPanel from './components/ChatPanel'
import Dashboard from './pages/Dashboard'
import SatelliteList from './pages/SatelliteList'
import SatelliteDetail from './pages/SatelliteDetail'
import MapView from './pages/MapView'
import SSADashboard from './pages/SSADashboard'
import ThreatDashboard from './pages/ThreatDashboard'
import MissionDashboard from './pages/MissionDashboard'
import AlarmDashboard from './pages/AlarmDashboard'
import OrbitalView from './pages/OrbitalView'
import { useSocketConnection } from './hooks'

function App() {
  // Initialize socket connection with automatic reconnection
  const { connectionState, isConnected } = useSocketConnection()

  return (
    <PageErrorBoundary>
      <Layout connectionState={connectionState} isConnected={isConnected}>
        <Routes>
          <Route path="/" element={<Dashboard />} />
          <Route path="/satellites" element={<SatelliteList />} />
          <Route path="/satellites/:id" element={<SatelliteDetail />} />
          <Route path="/threats" element={<ThreatDashboard />} />
          <Route path="/missions" element={<MissionDashboard />} />
          <Route path="/alarms" element={<AlarmDashboard />} />
          <Route path="/orbital" element={<OrbitalView />} />
          <Route path="/map" element={<MapView />} />
          <Route path="/ssa" element={<SSADashboard />} />
        </Routes>
        <ChatPanel />
      </Layout>
    </PageErrorBoundary>
  )
}

export default App
