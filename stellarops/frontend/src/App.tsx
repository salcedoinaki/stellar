import { Routes, Route } from 'react-router-dom'
import Layout from './components/Layout'
import Dashboard from './pages/Dashboard'
import SatelliteList from './pages/SatelliteList'
import SatelliteDetail from './pages/SatelliteDetail'
import MapView from './pages/MapView'
import SSADashboard from './pages/SSADashboard'
import AlarmDashboard from './pages/AlarmDashboard'
import MissionDashboard from './pages/MissionDashboard'
import { useSocketConnection } from './hooks'

function App() {
  // Initialize socket connection with automatic reconnection
  const { connectionState, isConnected } = useSocketConnection()

  return (
    <Layout connectionState={connectionState} isConnected={isConnected}>
      <Routes>
        <Route path="/" element={<Dashboard />} />
        <Route path="/satellites" element={<SatelliteList />} />
        <Route path="/satellites/:id" element={<SatelliteDetail />} />
        <Route path="/map" element={<MapView />} />
        <Route path="/ssa" element={<SSADashboard />} />
        <Route path="/alarms" element={<AlarmDashboard />} />
        <Route path="/missions" element={<MissionDashboard />} />
      </Routes>
    </Layout>
  )
}

export default App
