import { describe, it, expect, vi, beforeEach } from 'vitest';
import { render, screen, fireEvent, waitFor } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { MissionDashboard } from './MissionDashboard';
import { useSatelliteStore } from '../store/satelliteStore';

// Mock the store
vi.mock('../store/satelliteStore', () => ({
  useSatelliteStore: vi.fn()
}));

// Mock recharts
vi.mock('recharts', () => ({
  ResponsiveContainer: ({ children }: any) => <div>{children}</div>,
  BarChart: ({ children }: any) => <div data-testid="bar-chart">{children}</div>,
  Bar: () => null,
  XAxis: () => null,
  YAxis: () => null,
  Tooltip: () => null,
  Legend: () => null,
  PieChart: ({ children }: any) => <div data-testid="pie-chart">{children}</div>,
  Pie: () => null,
  Cell: () => null,
}));

const mockMissions = [
  {
    id: 'mission-1',
    name: 'Earth Observation Alpha',
    type: 'observation',
    satellite_id: 'sat-1',
    status: 'running',
    priority: 'high',
    scheduled_start: '2026-01-23T10:00:00Z',
    scheduled_end: '2026-01-23T12:00:00Z',
    actual_start: '2026-01-23T10:05:00Z',
    actual_end: null,
    required_energy: 25,
    required_memory: 512,
    progress: 65,
    created_at: '2026-01-22T15:00:00Z',
  },
  {
    id: 'mission-2',
    name: 'Data Downlink Bravo',
    type: 'downlink',
    satellite_id: 'sat-1',
    status: 'pending',
    priority: 'medium',
    scheduled_start: '2026-01-23T14:00:00Z',
    scheduled_end: '2026-01-23T14:30:00Z',
    actual_start: null,
    actual_end: null,
    required_energy: 15,
    required_memory: 256,
    progress: 0,
    created_at: '2026-01-22T16:00:00Z',
  },
  {
    id: 'mission-3',
    name: 'Maneuver Charlie',
    type: 'maneuver',
    satellite_id: 'sat-2',
    status: 'completed',
    priority: 'critical',
    scheduled_start: '2026-01-22T08:00:00Z',
    scheduled_end: '2026-01-22T08:15:00Z',
    actual_start: '2026-01-22T08:00:00Z',
    actual_end: '2026-01-22T08:12:00Z',
    required_energy: 50,
    required_memory: 128,
    progress: 100,
    created_at: '2026-01-21T20:00:00Z',
  },
  {
    id: 'mission-4',
    name: 'Calibration Delta',
    type: 'calibration',
    satellite_id: 'sat-1',
    status: 'failed',
    priority: 'low',
    scheduled_start: '2026-01-22T12:00:00Z',
    scheduled_end: '2026-01-22T12:30:00Z',
    actual_start: '2026-01-22T12:00:00Z',
    actual_end: '2026-01-22T12:10:00Z',
    required_energy: 10,
    required_memory: 64,
    progress: 35,
    error: 'Insufficient energy',
    created_at: '2026-01-21T18:00:00Z',
  },
];

const mockStats = {
  total: 4,
  running: 1,
  pending: 1,
  completed: 1,
  failed: 1,
  success_rate: 0.5,
};

describe('MissionDashboard', () => {
  const mockFetchMissions = vi.fn();
  const mockCreateMission = vi.fn();
  const mockCancelMission = vi.fn();

  beforeEach(() => {
    vi.clearAllMocks();
    (useSatelliteStore as any).mockReturnValue({
      missions: mockMissions,
      missionStats: mockStats,
      fetchMissions: mockFetchMissions,
      createMission: mockCreateMission,
      cancelMission: mockCancelMission,
      loading: false,
      error: null,
    });
  });

  it('renders mission dashboard title', () => {
    render(<MissionDashboard />);
    expect(screen.getByText(/mission/i)).toBeInTheDocument();
  });

  it('displays mission statistics', () => {
    render(<MissionDashboard />);
    
    expect(screen.getByText(/running.*1|1.*running/i)).toBeInTheDocument();
    expect(screen.getByText(/pending.*1|1.*pending/i)).toBeInTheDocument();
    expect(screen.getByText(/completed.*1|1.*completed/i)).toBeInTheDocument();
    expect(screen.getByText(/failed.*1|1.*failed/i)).toBeInTheDocument();
  });

  it('shows all missions in list', () => {
    render(<MissionDashboard />);
    
    expect(screen.getByText('Earth Observation Alpha')).toBeInTheDocument();
    expect(screen.getByText('Data Downlink Bravo')).toBeInTheDocument();
    expect(screen.getByText('Maneuver Charlie')).toBeInTheDocument();
    expect(screen.getByText('Calibration Delta')).toBeInTheDocument();
  });

  it('displays status badges', () => {
    render(<MissionDashboard />);
    
    expect(screen.getByText(/running/i)).toBeInTheDocument();
    expect(screen.getByText(/pending/i)).toBeInTheDocument();
    expect(screen.getByText(/completed/i)).toBeInTheDocument();
    expect(screen.getByText(/failed/i)).toBeInTheDocument();
  });

  it('shows progress bar for running missions', () => {
    render(<MissionDashboard />);
    
    const progressBar = screen.getByRole('progressbar');
    expect(progressBar).toHaveAttribute('aria-valuenow', '65');
  });

  it('filters missions by status', async () => {
    render(<MissionDashboard />);
    
    const statusFilter = screen.getByLabelText(/status|filter/i);
    fireEvent.change(statusFilter, { target: { value: 'running' } });
    
    await waitFor(() => {
      expect(screen.getByText('Earth Observation Alpha')).toBeInTheDocument();
      expect(screen.queryByText('Data Downlink Bravo')).not.toBeInTheDocument();
    });
  });

  it('filters missions by priority', async () => {
    render(<MissionDashboard />);
    
    const priorityFilter = screen.getByLabelText(/priority/i);
    fireEvent.change(priorityFilter, { target: { value: 'critical' } });
    
    await waitFor(() => {
      expect(screen.getByText('Maneuver Charlie')).toBeInTheDocument();
      expect(screen.queryByText('Earth Observation Alpha')).not.toBeInTheDocument();
    });
  });

  it('shows mission details on row click', async () => {
    render(<MissionDashboard />);
    
    const missionRow = screen.getByText('Earth Observation Alpha');
    fireEvent.click(missionRow);
    
    await waitFor(() => {
      expect(screen.getByText(/required.*energy.*25/i)).toBeInTheDocument();
      expect(screen.getByText(/required.*memory.*512/i)).toBeInTheDocument();
    });
  });

  it('calls cancelMission on cancel button click', async () => {
    render(<MissionDashboard />);
    
    const cancelButtons = screen.getAllByRole('button', { name: /cancel/i });
    fireEvent.click(cancelButtons[0]);
    
    // Confirm dialog
    const confirmButton = screen.getByRole('button', { name: /confirm|yes/i });
    fireEvent.click(confirmButton);
    
    await waitFor(() => {
      expect(mockCancelMission).toHaveBeenCalled();
    });
  });

  it('opens create mission modal', async () => {
    render(<MissionDashboard />);
    
    const createButton = screen.getByRole('button', { name: /create|new|add/i });
    fireEvent.click(createButton);
    
    await waitFor(() => {
      expect(screen.getByText(/create.*mission|new.*mission/i)).toBeInTheDocument();
    });
  });

  it('submits new mission form', async () => {
    mockCreateMission.mockResolvedValue({ id: 'new-mission' });
    
    render(<MissionDashboard />);
    
    // Open modal
    const createButton = screen.getByRole('button', { name: /create|new|add/i });
    fireEvent.click(createButton);
    
    // Fill form
    await userEvent.type(screen.getByLabelText(/name/i), 'New Mission');
    await userEvent.selectOptions(screen.getByLabelText(/type/i), 'observation');
    await userEvent.selectOptions(screen.getByLabelText(/satellite/i), 'sat-1');
    
    // Submit
    const submitButton = screen.getByRole('button', { name: /submit|create/i });
    fireEvent.click(submitButton);
    
    await waitFor(() => {
      expect(mockCreateMission).toHaveBeenCalled();
    });
  });

  it('shows loading state', () => {
    (useSatelliteStore as any).mockReturnValue({
      missions: [],
      missionStats: mockStats,
      fetchMissions: mockFetchMissions,
      loading: true,
      error: null,
    });
    
    render(<MissionDashboard />);
    expect(screen.getByText(/loading/i)).toBeInTheDocument();
  });

  it('shows error state', () => {
    (useSatelliteStore as any).mockReturnValue({
      missions: [],
      missionStats: mockStats,
      fetchMissions: mockFetchMissions,
      loading: false,
      error: 'Failed to fetch missions',
    });
    
    render(<MissionDashboard />);
    expect(screen.getByText(/error|failed/i)).toBeInTheDocument();
  });

  it('shows empty state when no missions', () => {
    (useSatelliteStore as any).mockReturnValue({
      missions: [],
      missionStats: { total: 0, running: 0, pending: 0, completed: 0, failed: 0, success_rate: 0 },
      fetchMissions: mockFetchMissions,
      loading: false,
      error: null,
    });
    
    render(<MissionDashboard />);
    expect(screen.getByText(/no.*missions/i)).toBeInTheDocument();
  });

  it('fetches missions on mount', () => {
    render(<MissionDashboard />);
    expect(mockFetchMissions).toHaveBeenCalled();
  });

  it('renders charts for statistics', () => {
    render(<MissionDashboard />);
    expect(screen.getByTestId('pie-chart')).toBeInTheDocument();
  });

  it('displays success rate', () => {
    render(<MissionDashboard />);
    expect(screen.getByText(/50%|0\.5/)).toBeInTheDocument();
  });

  it('sorts missions by priority', () => {
    render(<MissionDashboard />);
    
    const sortButton = screen.getByRole('button', { name: /sort.*priority/i });
    fireEvent.click(sortButton);
    
    const missionRows = screen.getAllByTestId('mission-row');
    expect(missionRows[0]).toHaveTextContent(/critical/i);
  });

  it('shows timeline view', async () => {
    render(<MissionDashboard />);
    
    const timelineTab = screen.getByRole('tab', { name: /timeline/i });
    fireEvent.click(timelineTab);
    
    await waitFor(() => {
      expect(screen.getByTestId('mission-timeline')).toBeInTheDocument();
    });
  });
});
