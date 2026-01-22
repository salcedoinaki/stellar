import { useEffect, useRef, useState } from 'react'
import type { SpaceObject, Conjunction, ThreatLevel } from '../types'

interface ThreatMapProps {
  spaceObjects: SpaceObject[]
  conjunctions: Conjunction[]
  protectedAssets: SpaceObject[]
  selectedObjectId?: string | null
  selectedConjunctionId?: string | null
  onSelectObject?: (id: string) => void
  onSelectConjunction?: (id: string) => void
  showDebris?: boolean
  showThreatHeatmap?: boolean
}

interface ObjectMarker {
  id: string
  x: number
  y: number
  type: 'protected' | 'threat' | 'debris' | 'neutral'
  threatLevel: ThreatLevel
  name: string
  noradId: number
}

interface ConjunctionLine {
  id: string
  x1: number
  y1: number
  x2: number
  y2: number
  severity: 'low' | 'medium' | 'high' | 'critical'
  tcaHours: number
}

const THREAT_COLORS: Record<ThreatLevel, string> = {
  none: '#6B7280',      // gray
  low: '#10B981',       // green
  medium: '#F59E0B',    // amber
  high: '#EF4444',      // red
  critical: '#DC2626',  // dark red
}

const SEVERITY_COLORS = {
  low: '#10B981',
  medium: '#F59E0B',
  high: '#EF4444',
  critical: '#DC2626',
}

export function ThreatMap({
  spaceObjects,
  conjunctions,
  protectedAssets,
  selectedObjectId,
  selectedConjunctionId,
  onSelectObject,
  onSelectConjunction,
  showDebris = false,
  showThreatHeatmap = true,
}: ThreatMapProps) {
  const svgRef = useRef<SVGSVGElement>(null)
  const [dimensions, setDimensions] = useState({ width: 800, height: 600 })
  const [hoveredObject, setHoveredObject] = useState<string | null>(null)
  const [viewBox, setViewBox] = useState({ x: -400, y: -300, width: 800, height: 600 })

  // Calculate responsive dimensions
  useEffect(() => {
    const updateDimensions = () => {
      if (svgRef.current?.parentElement) {
        const { width, height } = svgRef.current.parentElement.getBoundingClientRect()
        setDimensions({ width, height })
        setViewBox({ x: -width / 2, y: -height / 2, width, height })
      }
    }
    updateDimensions()
    window.addEventListener('resize', updateDimensions)
    return () => window.removeEventListener('resize', updateDimensions)
  }, [])

  // Convert orbital parameters to 2D visualization coordinates
  const objectToPosition = (obj: SpaceObject): { x: number; y: number } => {
    // Use a top-down orbital view (looking at Earth from above)
    // Map RAAN and mean anomaly to X/Y
    const raan = (obj.orbital_parameters.raan_deg || 0) * Math.PI / 180
    const ma = (obj.orbital_parameters.mean_anomaly_deg || 0) * Math.PI / 180
    const sma = obj.orbital_parameters.semi_major_axis_km || 7000 // Default LEO
    
    // Normalize to visualization scale
    const scale = Math.min(dimensions.width, dimensions.height) / 50000
    const radius = sma * scale
    const angle = raan + ma
    
    return {
      x: radius * Math.cos(angle),
      y: radius * Math.sin(angle)
    }
  }

  // Create markers for all objects
  const protectedIds = new Set(protectedAssets.map(a => a.id))
  
  const objectMarkers: ObjectMarker[] = spaceObjects
    .filter(obj => showDebris || obj.object_type !== 'debris')
    .map(obj => {
      const pos = objectToPosition(obj)
      let type: ObjectMarker['type'] = 'neutral'
      
      if (protectedIds.has(obj.id) || obj.is_protected_asset) {
        type = 'protected'
      } else if (obj.threat_assessment.threat_level === 'high' || 
                 obj.threat_assessment.threat_level === 'critical') {
        type = 'threat'
      } else if (obj.object_type === 'debris') {
        type = 'debris'
      }
      
      return {
        id: obj.id,
        x: pos.x,
        y: pos.y,
        type,
        threatLevel: obj.threat_assessment.threat_level,
        name: obj.name,
        noradId: obj.norad_id
      }
    })

  // Create conjunction lines
  const conjunctionLines: ConjunctionLine[] = conjunctions
    .filter(c => c.status !== 'passed')
    .map(c => {
      const primary = spaceObjects.find(o => o.id === c.primary_object?.id)
      const secondary = spaceObjects.find(o => o.id === c.secondary_object?.id)
      
      if (!primary || !secondary) {
        return null
      }
      
      const pos1 = objectToPosition(primary)
      const pos2 = objectToPosition(secondary)
      const tcaHours = (new Date(c.tca).getTime() - Date.now()) / (1000 * 60 * 60)
      
      return {
        id: c.id,
        x1: pos1.x,
        y1: pos1.y,
        x2: pos2.x,
        y2: pos2.y,
        severity: c.severity,
        tcaHours
      }
    })
    .filter((c): c is ConjunctionLine => c !== null)

  const getMarkerSize = (marker: ObjectMarker) => {
    if (marker.id === selectedObjectId) return 12
    if (marker.id === hoveredObject) return 10
    if (marker.type === 'protected') return 8
    if (marker.type === 'threat') return 7
    return 5
  }

  const getMarkerColor = (marker: ObjectMarker) => {
    if (marker.type === 'protected') return '#3B82F6' // blue
    if (marker.type === 'debris') return '#9CA3AF'   // gray
    return THREAT_COLORS[marker.threatLevel]
  }

  return (
    <div className="relative w-full h-full bg-slate-900 rounded-lg overflow-hidden">
      {/* Header info */}
      <div className="absolute top-4 left-4 z-10 text-white text-sm">
        <div className="bg-slate-800/80 rounded-lg p-3 space-y-1">
          <div className="flex items-center gap-2">
            <div className="w-3 h-3 rounded-full bg-blue-500" />
            <span>Protected Assets ({protectedAssets.length})</span>
          </div>
          <div className="flex items-center gap-2">
            <div className="w-3 h-3 rounded-full bg-red-500" />
            <span>Threats ({spaceObjects.filter(o => ['high', 'critical'].includes(o.threat_assessment.threat_level)).length})</span>
          </div>
          <div className="flex items-center gap-2">
            <div className="w-3 h-3 rounded-full bg-gray-400" />
            <span>Other Objects ({spaceObjects.filter(o => !['high', 'critical'].includes(o.threat_assessment.threat_level) && !o.is_protected_asset).length})</span>
          </div>
        </div>
      </div>

      {/* Conjunction count */}
      {conjunctions.length > 0 && (
        <div className="absolute top-4 right-4 z-10 text-white text-sm">
          <div className="bg-red-900/80 rounded-lg p-3">
            <div className="font-semibold">Active Conjunctions</div>
            <div className="text-2xl font-bold">{conjunctions.filter(c => c.status !== 'passed').length}</div>
            <div className="text-xs text-red-300">
              {conjunctions.filter(c => c.severity === 'critical').length} critical
            </div>
          </div>
        </div>
      )}

      {/* SVG Map */}
      <svg
        ref={svgRef}
        width="100%"
        height="100%"
        viewBox={`${viewBox.x} ${viewBox.y} ${viewBox.width} ${viewBox.height}`}
        className="cursor-crosshair"
      >
        {/* Background gradient */}
        <defs>
          <radialGradient id="earthGlow" cx="50%" cy="50%" r="50%">
            <stop offset="0%" stopColor="#1E40AF" stopOpacity="0.3" />
            <stop offset="100%" stopColor="#0F172A" stopOpacity="0" />
          </radialGradient>
          
          {/* Orbit rings */}
          <pattern id="orbitPattern" x="0" y="0" width="100" height="100" patternUnits="userSpaceOnUse">
            <circle cx="50" cy="50" r="40" fill="none" stroke="#1E293B" strokeWidth="0.5" />
          </pattern>
        </defs>

        {/* Earth representation at center */}
        <circle cx="0" cy="0" r="50" fill="url(#earthGlow)" />
        <circle cx="0" cy="0" r="20" fill="#1E40AF" />
        
        {/* Orbital rings */}
        {[100, 150, 200, 250, 300].map(r => (
          <circle 
            key={r}
            cx="0" 
            cy="0" 
            r={r} 
            fill="none" 
            stroke="#1E293B" 
            strokeWidth="1" 
            strokeDasharray="5 5"
          />
        ))}

        {/* Threat heatmap (background glow for high-threat areas) */}
        {showThreatHeatmap && objectMarkers
          .filter(m => m.type === 'threat')
          .map(marker => (
            <circle
              key={`heatmap-${marker.id}`}
              cx={marker.x}
              cy={marker.y}
              r={30}
              fill={THREAT_COLORS[marker.threatLevel]}
              opacity={0.15}
            />
          ))
        }

        {/* Conjunction lines */}
        {conjunctionLines.map(line => (
          <g key={`conjunction-${line.id}`}>
            <line
              x1={line.x1}
              y1={line.y1}
              x2={line.x2}
              y2={line.y2}
              stroke={SEVERITY_COLORS[line.severity]}
              strokeWidth={selectedConjunctionId === line.id ? 3 : 2}
              strokeDasharray={line.tcaHours > 24 ? "5 5" : undefined}
              opacity={0.8}
              className="cursor-pointer"
              onClick={() => onSelectConjunction?.(line.id)}
            />
            {/* TCA indicator at midpoint */}
            <circle
              cx={(line.x1 + line.x2) / 2}
              cy={(line.y1 + line.y2) / 2}
              r={5}
              fill={SEVERITY_COLORS[line.severity]}
              className="cursor-pointer"
              onClick={() => onSelectConjunction?.(line.id)}
            />
          </g>
        ))}

        {/* Object markers */}
        {objectMarkers.map(marker => (
          <g key={marker.id}>
            <circle
              cx={marker.x}
              cy={marker.y}
              r={getMarkerSize(marker)}
              fill={getMarkerColor(marker)}
              stroke={marker.id === selectedObjectId ? '#FFFFFF' : 'none'}
              strokeWidth={2}
              className="cursor-pointer transition-all duration-200"
              onClick={() => onSelectObject?.(marker.id)}
              onMouseEnter={() => setHoveredObject(marker.id)}
              onMouseLeave={() => setHoveredObject(null)}
            />
            
            {/* Protected asset indicator */}
            {marker.type === 'protected' && (
              <circle
                cx={marker.x}
                cy={marker.y}
                r={getMarkerSize(marker) + 3}
                fill="none"
                stroke="#3B82F6"
                strokeWidth={1}
                strokeDasharray="3 2"
              />
            )}
          </g>
        ))}

        {/* Hover tooltip */}
        {hoveredObject && (
          (() => {
            const marker = objectMarkers.find(m => m.id === hoveredObject)
            if (!marker) return null
            return (
              <g transform={`translate(${marker.x + 15}, ${marker.y - 10})`}>
                <rect
                  x="0"
                  y="0"
                  width="140"
                  height="45"
                  fill="#1E293B"
                  rx="4"
                  opacity="0.95"
                />
                <text x="8" y="16" fill="#F8FAFC" fontSize="11" fontWeight="bold">
                  {marker.name.substring(0, 18)}
                </text>
                <text x="8" y="30" fill="#94A3B8" fontSize="10">
                  NORAD: {marker.noradId}
                </text>
                <text x="8" y="42" fill={THREAT_COLORS[marker.threatLevel]} fontSize="10">
                  Threat: {marker.threatLevel.toUpperCase()}
                </text>
              </g>
            )
          })()
        )}
      </svg>

      {/* Zoom controls */}
      <div className="absolute bottom-4 right-4 z-10 flex flex-col gap-2">
        <button
          onClick={() => setViewBox(v => ({
            ...v,
            x: v.x * 0.8,
            y: v.y * 0.8,
            width: v.width * 0.8,
            height: v.height * 0.8
          }))}
          className="bg-slate-700 hover:bg-slate-600 text-white w-8 h-8 rounded flex items-center justify-center"
        >
          +
        </button>
        <button
          onClick={() => setViewBox(v => ({
            ...v,
            x: v.x * 1.2,
            y: v.y * 1.2,
            width: v.width * 1.2,
            height: v.height * 1.2
          }))}
          className="bg-slate-700 hover:bg-slate-600 text-white w-8 h-8 rounded flex items-center justify-center"
        >
          -
        </button>
        <button
          onClick={() => setViewBox({ 
            x: -dimensions.width / 2, 
            y: -dimensions.height / 2, 
            width: dimensions.width, 
            height: dimensions.height 
          })}
          className="bg-slate-700 hover:bg-slate-600 text-white w-8 h-8 rounded flex items-center justify-center text-xs"
        >
          ⟲
        </button>
      </div>
    </div>
  )
}

export default ThreatMap
