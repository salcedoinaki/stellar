import { Routes, Route } from 'react-router-dom'
import { useEffect } from 'react'
import Layout from './components/Layout'
import ChatPanel from './components/ChatPanel'
import Dashboard from './pages/Dashboard'
import SatelliteList from './pages/SatelliteList'
import SatelliteDetail from './pages/SatelliteDetail'
import MapView from './pages/MapView'
import ThreatDashboard from './pages/ThreatDashboard'
import MissionDashboard from './pages/MissionDashboard'
import AlarmDashboard from './pages/AlarmDashboard'
import OrbitalView from './pages/OrbitalView'
import { useSatelliteStore } from './store/satelliteStore'
import { socketService } from './services/socket'

function App() {
  const { addTelemetry, updateSatellite } = useSatelliteStore()

  useEffect(() => {
    // Connect to Phoenix WebSocket
    socketService.connect()

    // Join the satellites lobby channel
    const channel = socketService.joinChannel('satellites:lobby')

    if (channel) {
      // Listen for satellite state changes
      channel.on('satellite_updated', (payload) => {
        updateSatellite(payload.satellite_id, payload)
      })

      // Listen for telemetry events
      channel.on('telemetry_event', (payload) => {
        addTelemetry(payload.satellite_id, payload)
      })

      // Listen for mode changes
      channel.on('mode_changed', (payload) => {
        updateSatellite(payload.satellite_id, { mode: payload.new_mode })
      })
    }

    return () => {
      socketService.disconnect()
    }
  }, [addTelemetry, updateSatellite])

  return (
    <Layout>
      <Routes>
        <Route path="/" element={<Dashboard />} />
        <Route path="/satellites" element={<SatelliteList />} />
        <Route path="/satellites/:id" element={<SatelliteDetail />} />
        <Route path="/threats" element={<ThreatDashboard />} />
        <Route path="/missions" element={<MissionDashboard />} />
        <Route path="/alarms" element={<AlarmDashboard />} />
        <Route path="/orbital" element={<OrbitalView />} />
        <Route path="/map" element={<MapView />} />
      </Routes>
      <ChatPanel />
    </Layout>
  )
}

export default App
