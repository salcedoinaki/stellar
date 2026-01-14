import {
  LineChart,
  Line,
  XAxis,
  YAxis,
  CartesianGrid,
  Tooltip,
  ResponsiveContainer,
  Legend,
} from 'recharts'
import type { TelemetryData } from '../types'

interface TelemetryChartProps {
  data: TelemetryData[]
  title?: string
  height?: number
}

export default function TelemetryChart({ data, title, height = 300 }: TelemetryChartProps) {
  const chartData = data.map((point) => ({
    ...point,
    time: new Date(point.timestamp).toLocaleTimeString(),
  }))

  if (data.length === 0) {
    return (
      <div className="bg-slate-800 rounded-xl p-5 border border-slate-700">
        {title && <h3 className="text-lg font-semibold text-white mb-4">{title}</h3>}
        <div className="flex items-center justify-center h-48 text-slate-400">
          No telemetry data available
        </div>
      </div>
    )
  }

  return (
    <div className="bg-slate-800 rounded-xl p-5 border border-slate-700">
      {title && <h3 className="text-lg font-semibold text-white mb-4">{title}</h3>}
      <ResponsiveContainer width="100%" height={height}>
        <LineChart data={chartData}>
          <CartesianGrid strokeDasharray="3 3" stroke="#334155" />
          <XAxis
            dataKey="time"
            stroke="#64748b"
            fontSize={12}
            tickLine={false}
          />
          <YAxis
            stroke="#64748b"
            fontSize={12}
            tickLine={false}
            domain={[0, 100]}
          />
          <Tooltip
            contentStyle={{
              backgroundColor: '#1e293b',
              border: '1px solid #334155',
              borderRadius: '8px',
              color: '#e2e8f0',
            }}
          />
          <Legend />
          <Line
            type="monotone"
            dataKey="energy"
            stroke="#22c55e"
            strokeWidth={2}
            dot={false}
            name="Energy %"
          />
          <Line
            type="monotone"
            dataKey="memory"
            stroke="#f59e0b"
            strokeWidth={2}
            dot={false}
            name="Memory %"
          />
          {data[0]?.temperature !== undefined && (
            <Line
              type="monotone"
              dataKey="temperature"
              stroke="#ef4444"
              strokeWidth={2}
              dot={false}
              name="Temperature °C"
            />
          )}
        </LineChart>
      </ResponsiveContainer>
    </div>
  )
}

interface StatCardProps {
  label: string
  value: string | number
  unit?: string
  trend?: 'up' | 'down' | 'stable'
  color?: 'green' | 'yellow' | 'red' | 'blue'
}

export function StatCard({ label, value, unit, trend, color = 'blue' }: StatCardProps) {
  const colorClasses = {
    green: 'text-green-400',
    yellow: 'text-yellow-400',
    red: 'text-red-400',
    blue: 'text-stellar-400',
  }

  const trendIcons = {
    up: '↑',
    down: '↓',
    stable: '→',
  }

  return (
    <div className="bg-slate-800 rounded-xl p-4 border border-slate-700">
      <div className="text-sm text-slate-400 mb-1">{label}</div>
      <div className="flex items-baseline gap-1">
        <span className={`text-2xl font-bold ${colorClasses[color]}`}>{value}</span>
        {unit && <span className="text-sm text-slate-400">{unit}</span>}
        {trend && (
          <span
            className={`ml-2 ${
              trend === 'up'
                ? 'text-green-400'
                : trend === 'down'
                ? 'text-red-400'
                : 'text-slate-400'
            }`}
          >
            {trendIcons[trend]}
          </span>
        )}
      </div>
    </div>
  )
}
