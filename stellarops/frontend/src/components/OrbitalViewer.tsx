import { useRef, useEffect, useCallback, useState } from 'react'
import type { Satellite, Conjunction, SpaceObject, GroundStation } from '../types'
import { api } from '../services/api'

interface OrbitalViewerProps {
  satellites?: Satellite[]
  conjunctions?: Conjunction[]
  groundStations?: GroundStation[]
  selectedConjunctionId?: string
  onSelectSatellite?: (id: string) => void
  onSelectConjunction?: (id: string) => void
}

// Earth constants
const EARTH_RADIUS_KM = 6371
const SCALE_FACTOR = 0.001 // 1 unit = 1000 km

interface ViewerState {
  camera: {
    distance: number
    azimuth: number
    elevation: number
  }
  showOrbits: boolean
  showGroundStations: boolean
  showLabels: boolean
  animationSpeed: number
  is3D: boolean
}

export default function OrbitalViewer({
  satellites = [],
  conjunctions = [],
  groundStations = [],
  selectedConjunctionId,
  onSelectSatellite,
  onSelectConjunction,
}: OrbitalViewerProps) {
  const canvasRef = useRef<HTMLCanvasElement>(null)
  const [viewerState, setViewerState] = useState<ViewerState>({
    camera: {
      distance: 50,
      azimuth: 45,
      elevation: 30,
    },
    showOrbits: true,
    showGroundStations: true,
    showLabels: true,
    animationSpeed: 1,
    is3D: true,
  })
  const [hoveredObject, setHoveredObject] = useState<string | null>(null)
  const [tooltip, setTooltip] = useState<{ x: number; y: number; content: string } | null>(null)
  const animationRef = useRef<number>()
  const dragRef = useRef<{ x: number; y: number } | null>(null)

  // Render the scene
  const render = useCallback(() => {
    const canvas = canvasRef.current
    if (!canvas) return

    const ctx = canvas.getContext('2d')
    if (!ctx) return

    const { width, height } = canvas
    const centerX = width / 2
    const centerY = height / 2
    const { camera, showOrbits, showGroundStations, showLabels, is3D } = viewerState

    // Clear canvas
    ctx.fillStyle = '#0f172a'
    ctx.fillRect(0, 0, width, height)

    // Draw stars background
    ctx.fillStyle = '#ffffff'
    for (let i = 0; i < 200; i++) {
      const x = ((i * 17) % width)
      const y = ((i * 31) % height)
      const size = (i % 3) * 0.5 + 0.5
      ctx.beginPath()
      ctx.arc(x, y, size, 0, Math.PI * 2)
      ctx.fill()
    }

    // Project 3D to 2D
    const project = (x: number, y: number, z: number): [number, number, number] => {
      if (!is3D) {
        // 2D top-down view
        return [centerX + x * 3, centerY + z * 3, 1]
      }
      
      const cosA = Math.cos((camera.azimuth * Math.PI) / 180)
      const sinA = Math.sin((camera.azimuth * Math.PI) / 180)
      const cosE = Math.cos((camera.elevation * Math.PI) / 180)
      const sinE = Math.sin((camera.elevation * Math.PI) / 180)

      // Rotate
      const x1 = x * cosA - z * sinA
      const z1 = x * sinA + z * cosA
      const y1 = y * cosE - z1 * sinE
      const z2 = y * sinE + z1 * cosE

      // Perspective projection
      const scale = camera.distance / (camera.distance + z2)
      const projX = centerX + x1 * scale * 5
      const projY = centerY - y1 * scale * 5

      return [projX, projY, scale]
    }

    // Draw Earth
    const earthRadius = EARTH_RADIUS_KM * SCALE_FACTOR
    const [earthX, earthY, earthScale] = project(0, 0, 0)
    const earthVisibleRadius = earthRadius * earthScale * 5

    // Earth gradient
    const gradient = ctx.createRadialGradient(
      earthX - earthVisibleRadius * 0.3,
      earthY - earthVisibleRadius * 0.3,
      0,
      earthX,
      earthY,
      earthVisibleRadius
    )
    gradient.addColorStop(0, '#4fb8ff')
    gradient.addColorStop(0.7, '#1e3a5f')
    gradient.addColorStop(1, '#0a1628')

    ctx.beginPath()
    ctx.arc(earthX, earthY, earthVisibleRadius, 0, Math.PI * 2)
    ctx.fillStyle = gradient
    ctx.fill()

    // Draw ground stations on Earth surface
    if (showGroundStations) {
      groundStations.forEach((station) => {
        const lat = (station.latitude * Math.PI) / 180
        const lon = (station.longitude * Math.PI) / 180
        const gsX = earthRadius * Math.cos(lat) * Math.cos(lon)
        const gsY = earthRadius * Math.sin(lat)
        const gsZ = earthRadius * Math.cos(lat) * Math.sin(lon)
        const [px, py, scale] = project(gsX, gsY, gsZ)

        if (scale > 0.5) {
          ctx.fillStyle = '#22c55e'
          ctx.beginPath()
          ctx.arc(px, py, 4, 0, Math.PI * 2)
          ctx.fill()

          if (showLabels) {
            ctx.fillStyle = '#94a3b8'
            ctx.font = '10px monospace'
            ctx.fillText(station.name, px + 6, py + 3)
          }
        }
      })
    }

    // Draw orbits and satellites
    satellites.forEach((satellite, index) => {
      // Estimate orbit from altitude (simplified circular orbit)
      const altitude = satellite.altitude || 400
      const orbitRadius = (EARTH_RADIUS_KM + altitude) * SCALE_FACTOR

      // Draw orbit path
      if (showOrbits) {
        ctx.strokeStyle = '#334155'
        ctx.lineWidth = 1
        ctx.beginPath()
        for (let angle = 0; angle <= 360; angle += 5) {
          const rad = (angle * Math.PI) / 180
          const ox = orbitRadius * Math.cos(rad)
          const oz = orbitRadius * Math.sin(rad)
          const [px, py] = project(ox, 0, oz)
          if (angle === 0) ctx.moveTo(px, py)
          else ctx.lineTo(px, py)
        }
        ctx.closePath()
        ctx.stroke()
      }

      // Satellite position (animate)
      const time = Date.now() / 1000
      const orbitPeriod = 90 * 60 // 90 min orbit in seconds
      const angle = ((time * viewerState.animationSpeed) / orbitPeriod + index * 0.3) * Math.PI * 2
      const satX = orbitRadius * Math.cos(angle)
      const satZ = orbitRadius * Math.sin(angle)
      const satY = Math.sin(angle * 0.5) * orbitRadius * 0.1 // Slight inclination

      const [px, py, scale] = project(satX, satY, satZ)

      // Satellite marker
      const isWarning = satellite.mode === 'safe'
      const isCritical = satellite.mode === 'critical'
      ctx.fillStyle = isCritical ? '#ef4444' : isWarning ? '#f59e0b' : '#38bdf8'
      ctx.beginPath()
      ctx.arc(px, py, 5 * scale, 0, Math.PI * 2)
      ctx.fill()

      // Satellite label
      if (showLabels) {
        ctx.fillStyle = '#e2e8f0'
        ctx.font = '11px monospace'
        ctx.fillText(satellite.id.slice(0, 8), px + 8, py + 3)
      }
    })

    // Draw conjunctions
    const selectedConjunction = conjunctions.find((c) => c.id === selectedConjunctionId)
    conjunctions.forEach((conjunction) => {
      const isSelected = conjunction.id === selectedConjunctionId

      // Find associated satellite
      const asset = satellites.find((s) => s.id === conjunction.asset_id)
      if (!asset) return

      // Approximate threat object position
      const altitude = asset.altitude || 400
      const orbitRadius = (EARTH_RADIUS_KM + altitude) * SCALE_FACTOR
      const time = Date.now() / 1000
      const angle = ((time * viewerState.animationSpeed) / 5400 + 0.7) * Math.PI * 2

      const threatX = orbitRadius * Math.cos(angle)
      const threatZ = orbitRadius * Math.sin(angle)
      const [tx, ty, tScale] = project(threatX, 0, threatZ)

      // Threat object marker
      const severityColors = {
        critical: '#ef4444',
        high: '#f97316',
        medium: '#eab308',
        low: '#22c55e',
      }
      ctx.fillStyle = severityColors[conjunction.severity] || '#64748b'
      ctx.beginPath()
      if (isSelected) {
        // Pulsing effect for selected
        const pulse = Math.sin(Date.now() / 200) * 2 + 8
        ctx.arc(tx, ty, pulse * tScale, 0, Math.PI * 2)
      } else {
        ctx.arc(tx, ty, 6 * tScale, 0, Math.PI * 2)
      }
      ctx.fill()

      // Draw conjunction line (if selected)
      if (isSelected && asset) {
        // Get asset position (approximate)
        const assetAngle = ((time * viewerState.animationSpeed) / 5400) * Math.PI * 2
        const assetX = orbitRadius * Math.cos(assetAngle)
        const assetZ = orbitRadius * Math.sin(assetAngle)
        const [ax, ay] = project(assetX, 0, assetZ)

        ctx.strokeStyle = '#ef4444'
        ctx.lineWidth = 2
        ctx.setLineDash([5, 5])
        ctx.beginPath()
        ctx.moveTo(ax, ay)
        ctx.lineTo(tx, ty)
        ctx.stroke()
        ctx.setLineDash([])

        // Closest approach annotation
        const midX = (ax + tx) / 2
        const midY = (ay + ty) / 2
        ctx.fillStyle = '#ef4444'
        ctx.font = 'bold 11px monospace'
        ctx.fillText(`${conjunction.miss_distance_km.toFixed(1)} km`, midX, midY - 10)
      }
    })

    // Schedule next frame
    animationRef.current = requestAnimationFrame(render)
  }, [satellites, conjunctions, groundStations, viewerState, selectedConjunctionId])

  // Initialize and cleanup
  useEffect(() => {
    const canvas = canvasRef.current
    if (!canvas) return

    // Set canvas size
    const updateSize = () => {
      const rect = canvas.getBoundingClientRect()
      canvas.width = rect.width
      canvas.height = rect.height
    }
    updateSize()
    window.addEventListener('resize', updateSize)

    // Start rendering
    render()

    return () => {
      window.removeEventListener('resize', updateSize)
      if (animationRef.current) {
        cancelAnimationFrame(animationRef.current)
      }
    }
  }, [render])

  // Mouse handlers
  const handleMouseDown = (e: React.MouseEvent) => {
    dragRef.current = { x: e.clientX, y: e.clientY }
  }

  const handleMouseMove = (e: React.MouseEvent) => {
    if (dragRef.current) {
      const dx = e.clientX - dragRef.current.x
      const dy = e.clientY - dragRef.current.y

      setViewerState((prev) => ({
        ...prev,
        camera: {
          ...prev.camera,
          azimuth: prev.camera.azimuth + dx * 0.5,
          elevation: Math.max(-90, Math.min(90, prev.camera.elevation - dy * 0.5)),
        },
      }))

      dragRef.current = { x: e.clientX, y: e.clientY }
    }
  }

  const handleMouseUp = () => {
    dragRef.current = null
  }

  const handleWheel = (e: React.WheelEvent) => {
    e.preventDefault()
    setViewerState((prev) => ({
      ...prev,
      camera: {
        ...prev.camera,
        distance: Math.max(20, Math.min(200, prev.camera.distance + e.deltaY * 0.1)),
      },
    }))
  }

  return (
    <div className="relative w-full h-full bg-slate-900 rounded-lg overflow-hidden">
      <canvas
        ref={canvasRef}
        className="w-full h-full cursor-grab active:cursor-grabbing"
        onMouseDown={handleMouseDown}
        onMouseMove={handleMouseMove}
        onMouseUp={handleMouseUp}
        onMouseLeave={handleMouseUp}
        onWheel={handleWheel}
      />

      {/* Controls */}
      <div className="absolute top-4 left-4 bg-slate-800/90 rounded-lg p-3 space-y-2">
        <h3 className="text-sm font-semibold text-white mb-2">View Controls</h3>
        
        <label className="flex items-center gap-2 text-xs text-slate-300">
          <input
            type="checkbox"
            checked={viewerState.is3D}
            onChange={(e) => setViewerState((prev) => ({ ...prev, is3D: e.target.checked }))}
            className="rounded"
          />
          3D View
        </label>

        <label className="flex items-center gap-2 text-xs text-slate-300">
          <input
            type="checkbox"
            checked={viewerState.showOrbits}
            onChange={(e) => setViewerState((prev) => ({ ...prev, showOrbits: e.target.checked }))}
            className="rounded"
          />
          Show Orbits
        </label>

        <label className="flex items-center gap-2 text-xs text-slate-300">
          <input
            type="checkbox"
            checked={viewerState.showGroundStations}
            onChange={(e) => setViewerState((prev) => ({ ...prev, showGroundStations: e.target.checked }))}
            className="rounded"
          />
          Ground Stations
        </label>

        <label className="flex items-center gap-2 text-xs text-slate-300">
          <input
            type="checkbox"
            checked={viewerState.showLabels}
            onChange={(e) => setViewerState((prev) => ({ ...prev, showLabels: e.target.checked }))}
            className="rounded"
          />
          Labels
        </label>

        <div className="pt-2 border-t border-slate-700">
          <label className="text-xs text-slate-400">Animation Speed</label>
          <input
            type="range"
            min="0"
            max="10"
            step="0.5"
            value={viewerState.animationSpeed}
            onChange={(e) => setViewerState((prev) => ({ ...prev, animationSpeed: parseFloat(e.target.value) }))}
            className="w-full"
          />
        </div>
      </div>

      {/* Legend */}
      <div className="absolute bottom-4 left-4 bg-slate-800/90 rounded-lg p-3">
        <h3 className="text-xs font-semibold text-white mb-2">Legend</h3>
        <div className="space-y-1 text-xs">
          <div className="flex items-center gap-2">
            <div className="w-3 h-3 rounded-full bg-sky-400" />
            <span className="text-slate-300">Satellite (Nominal)</span>
          </div>
          <div className="flex items-center gap-2">
            <div className="w-3 h-3 rounded-full bg-amber-400" />
            <span className="text-slate-300">Satellite (Safe Mode)</span>
          </div>
          <div className="flex items-center gap-2">
            <div className="w-3 h-3 rounded-full bg-red-500" />
            <span className="text-slate-300">Critical / Threat</span>
          </div>
          <div className="flex items-center gap-2">
            <div className="w-3 h-3 rounded-full bg-green-500" />
            <span className="text-slate-300">Ground Station</span>
          </div>
        </div>
      </div>

      {/* Stats */}
      <div className="absolute top-4 right-4 bg-slate-800/90 rounded-lg p-3">
        <div className="text-xs text-slate-400 space-y-1">
          <div>Satellites: <span className="text-white">{satellites.length}</span></div>
          <div>Conjunctions: <span className="text-white">{conjunctions.length}</span></div>
          <div>Ground Stations: <span className="text-white">{groundStations.length}</span></div>
        </div>
      </div>

      {/* Tooltip */}
      {tooltip && (
        <div
          className="absolute bg-slate-900 border border-slate-700 rounded px-2 py-1 text-xs text-white pointer-events-none"
          style={{ left: tooltip.x + 10, top: tooltip.y + 10 }}
        >
          {tooltip.content}
        </div>
      )}
    </div>
  )
}
