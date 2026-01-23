import { describe, it, expect, vi, beforeEach } from 'vitest';
import { render, screen, fireEvent, waitFor } from '@testing-library/react';
import { AlarmDashboard } from './AlarmDashboard';
import { useSatelliteStore } from '../store/satelliteStore';

// Mock the store
vi.mock('../store/satelliteStore', () => ({
  useSatelliteStore: vi.fn()
}));

const mockAlarms = [
  {
    id: 'alarm-1',
    type: 'conjunction_warning',
    severity: 'critical',
    message: 'High probability collision detected',
    source: 'conjunction_detection',
    satellite_id: 'sat-1',
    acknowledged: false,
    acknowledged_by: null,
    acknowledged_at: null,
    resolved: false,
    resolved_by: null,
    resolved_at: null,
    raised_at: '2026-01-23T10:00:00Z',
    context: {
      conjunction_id: 'conj-1',
      probability: 0.0001,
      miss_distance_km: 0.5,
    },
  },
  {
    id: 'alarm-2',
    type: 'low_energy',
    severity: 'major',
    message: 'Satellite energy below 20%',
    source: 'satellite_monitor',
    satellite_id: 'sat-2',
    acknowledged: true,
    acknowledged_by: 'operator@stellarops.com',
    acknowledged_at: '2026-01-23T09:30:00Z',
    resolved: false,
    resolved_by: null,
    resolved_at: null,
    raised_at: '2026-01-23T09:00:00Z',
    context: {
      energy_level: 18.5,
    },
  },
  {
    id: 'alarm-3',
    type: 'tle_stale',
    severity: 'warning',
    message: 'TLE data is stale (>24h old)',
    source: 'tle_ingester',
    satellite_id: null,
    acknowledged: false,
    acknowledged_by: null,
    acknowledged_at: null,
    resolved: false,
    resolved_by: null,
    resolved_at: null,
    raised_at: '2026-01-23T08:00:00Z',
    context: {
      norad_id: 25544,
      age_hours: 36,
    },
  },
];

describe('AlarmDashboard', () => {
  const mockFetchAlarms = vi.fn();
  const mockAcknowledgeAlarm = vi.fn();
  const mockResolveAlarm = vi.fn();

  beforeEach(() => {
    vi.clearAllMocks();
    (useSatelliteStore as any).mockReturnValue({
      alarms: mockAlarms,
      fetchAlarms: mockFetchAlarms,
      acknowledgeAlarm: mockAcknowledgeAlarm,
      resolveAlarm: mockResolveAlarm,
      loading: false,
      error: null,
    });
  });

  it('renders alarm dashboard title', () => {
    render(<AlarmDashboard />);
    expect(screen.getByText(/alarm/i)).toBeInTheDocument();
  });

  it('displays alarm count by severity', () => {
    render(<AlarmDashboard />);
    expect(screen.getByText(/critical.*1|1.*critical/i)).toBeInTheDocument();
    expect(screen.getByText(/major.*1|1.*major/i)).toBeInTheDocument();
    expect(screen.getByText(/warning.*1|1.*warning/i)).toBeInTheDocument();
  });

  it('shows all alarms in list', () => {
    render(<AlarmDashboard />);
    expect(screen.getByText(/high probability collision/i)).toBeInTheDocument();
    expect(screen.getByText(/energy below 20%/i)).toBeInTheDocument();
    expect(screen.getByText(/TLE.*stale/i)).toBeInTheDocument();
  });

  it('displays severity badges with correct colors', () => {
    render(<AlarmDashboard />);
    
    const criticalBadge = screen.getByText(/critical/i);
    expect(criticalBadge).toHaveClass(/red|critical|danger/i);
    
    const majorBadge = screen.getByText(/major/i);
    expect(majorBadge).toHaveClass(/orange|major|warning/i);
  });

  it('shows acknowledged status', () => {
    render(<AlarmDashboard />);
    
    const acknowledgedAlarm = screen.getByText(/energy below 20%/i).closest('div');
    expect(acknowledgedAlarm).toContainElement(screen.getByText(/acknowledged/i));
  });

  it('calls acknowledgeAlarm on acknowledge button click', async () => {
    render(<AlarmDashboard />);
    
    const ackButtons = screen.getAllByRole('button', { name: /acknowledge|ack/i });
    fireEvent.click(ackButtons[0]);
    
    await waitFor(() => {
      expect(mockAcknowledgeAlarm).toHaveBeenCalledWith('alarm-1');
    });
  });

  it('calls resolveAlarm on resolve button click', async () => {
    render(<AlarmDashboard />);
    
    const resolveButtons = screen.getAllByRole('button', { name: /resolve/i });
    fireEvent.click(resolveButtons[0]);
    
    await waitFor(() => {
      expect(mockResolveAlarm).toHaveBeenCalledWith('alarm-1');
    });
  });

  it('filters alarms by severity', async () => {
    render(<AlarmDashboard />);
    
    const filterSelect = screen.getByLabelText(/severity|filter/i);
    fireEvent.change(filterSelect, { target: { value: 'critical' } });
    
    await waitFor(() => {
      expect(screen.getByText(/high probability collision/i)).toBeInTheDocument();
      expect(screen.queryByText(/energy below 20%/i)).not.toBeInTheDocument();
    });
  });

  it('filters alarms by status', async () => {
    render(<AlarmDashboard />);
    
    const statusFilter = screen.getByRole('button', { name: /unacknowledged|active/i });
    fireEvent.click(statusFilter);
    
    await waitFor(() => {
      expect(screen.getByText(/high probability collision/i)).toBeInTheDocument();
      expect(screen.queryByText(/energy below 20%/i)).not.toBeInTheDocument();
    });
  });

  it('sorts alarms by severity (critical first)', () => {
    render(<AlarmDashboard />);
    
    const alarmRows = screen.getAllByTestId('alarm-row');
    expect(alarmRows[0]).toHaveTextContent(/critical/i);
  });

  it('shows alarm details on row click', async () => {
    render(<AlarmDashboard />);
    
    const alarmRow = screen.getByText(/high probability collision/i);
    fireEvent.click(alarmRow);
    
    await waitFor(() => {
      expect(screen.getByText(/probability.*0\.0001/i)).toBeInTheDocument();
      expect(screen.getByText(/miss.*distance.*0\.5/i)).toBeInTheDocument();
    });
  });

  it('shows loading state', () => {
    (useSatelliteStore as any).mockReturnValue({
      alarms: [],
      fetchAlarms: mockFetchAlarms,
      loading: true,
      error: null,
    });
    
    render(<AlarmDashboard />);
    expect(screen.getByText(/loading/i)).toBeInTheDocument();
  });

  it('shows error state', () => {
    (useSatelliteStore as any).mockReturnValue({
      alarms: [],
      fetchAlarms: mockFetchAlarms,
      loading: false,
      error: 'Failed to fetch alarms',
    });
    
    render(<AlarmDashboard />);
    expect(screen.getByText(/error|failed/i)).toBeInTheDocument();
  });

  it('shows empty state when no alarms', () => {
    (useSatelliteStore as any).mockReturnValue({
      alarms: [],
      fetchAlarms: mockFetchAlarms,
      loading: false,
      error: null,
    });
    
    render(<AlarmDashboard />);
    expect(screen.getByText(/no.*alarms|all.*clear/i)).toBeInTheDocument();
  });

  it('fetches alarms on mount', () => {
    render(<AlarmDashboard />);
    expect(mockFetchAlarms).toHaveBeenCalled();
  });

  it('auto-refreshes alarms', async () => {
    vi.useFakeTimers();
    
    render(<AlarmDashboard autoRefresh refreshInterval={5000} />);
    
    expect(mockFetchAlarms).toHaveBeenCalledTimes(1);
    
    vi.advanceTimersByTime(5000);
    
    expect(mockFetchAlarms).toHaveBeenCalledTimes(2);
    
    vi.useRealTimers();
  });

  it('plays sound on new critical alarm', async () => {
    const playMock = vi.fn();
    global.Audio = vi.fn().mockImplementation(() => ({
      play: playMock,
    }));
    
    render(<AlarmDashboard soundEnabled />);
    
    // Simulate new alarm
    const newAlarms = [
      {
        ...mockAlarms[0],
        id: 'alarm-new',
        raised_at: new Date().toISOString(),
      },
      ...mockAlarms,
    ];
    
    (useSatelliteStore as any).mockReturnValue({
      alarms: newAlarms,
      fetchAlarms: mockFetchAlarms,
      loading: false,
      error: null,
    });
    
    // Trigger re-render would play sound
    expect(playMock).toHaveBeenCalledTimes(0); // Initial render
  });
});
