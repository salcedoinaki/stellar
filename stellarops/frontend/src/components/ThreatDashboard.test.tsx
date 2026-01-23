import { describe, it, expect, vi, beforeEach } from 'vitest';
import { render, screen, fireEvent, waitFor } from '@testing-library/react';
import { ThreatDashboard } from './ThreatDashboard';
import { useSatelliteStore } from '../store/satelliteStore';

// Mock the store
vi.mock('../store/satelliteStore', () => ({
  useSatelliteStore: vi.fn()
}));

// Mock recharts to avoid canvas issues
vi.mock('recharts', () => ({
  ResponsiveContainer: ({ children }: any) => <div>{children}</div>,
  PieChart: ({ children }: any) => <div data-testid="pie-chart">{children}</div>,
  Pie: () => null,
  Cell: () => null,
  BarChart: ({ children }: any) => <div data-testid="bar-chart">{children}</div>,
  Bar: () => null,
  XAxis: () => null,
  YAxis: () => null,
  Tooltip: () => null,
  Legend: () => null,
}));

describe('ThreatDashboard', () => {
  const mockThreats = [
    {
      id: '1',
      norad_id: 25544,
      name: 'ISS (ZARYA)',
      classification: 'friendly',
      threat_level: 'low',
      origin_country: 'International',
      last_updated: '2026-01-23T10:00:00Z',
    },
    {
      id: '2',
      norad_id: 43013,
      name: 'COSMOS 2542',
      classification: 'hostile',
      threat_level: 'high',
      origin_country: 'Russia',
      last_updated: '2026-01-23T09:00:00Z',
    },
    {
      id: '3',
      norad_id: 48274,
      name: 'USA 326',
      classification: 'unknown',
      threat_level: 'medium',
      origin_country: 'USA',
      last_updated: '2026-01-23T08:00:00Z',
    },
  ];

  beforeEach(() => {
    vi.clearAllMocks();
    (useSatelliteStore as any).mockReturnValue({
      threats: mockThreats,
      fetchThreats: vi.fn(),
      loading: false,
      error: null,
    });
  });

  it('renders the dashboard title', () => {
    render(<ThreatDashboard />);
    expect(screen.getByText(/threat/i)).toBeInTheDocument();
  });

  it('displays threat count summary', () => {
    render(<ThreatDashboard />);
    expect(screen.getByText('3')).toBeInTheDocument(); // Total threats
  });

  it('shows threats by classification', () => {
    render(<ThreatDashboard />);
    expect(screen.getByText(/friendly/i)).toBeInTheDocument();
    expect(screen.getByText(/hostile/i)).toBeInTheDocument();
    expect(screen.getByText(/unknown/i)).toBeInTheDocument();
  });

  it('displays threat level indicators', () => {
    render(<ThreatDashboard />);
    expect(screen.getByText(/high/i)).toBeInTheDocument();
    expect(screen.getByText(/medium/i)).toBeInTheDocument();
    expect(screen.getByText(/low/i)).toBeInTheDocument();
  });

  it('renders charts when data is available', () => {
    render(<ThreatDashboard />);
    expect(screen.getByTestId('pie-chart')).toBeInTheDocument();
  });

  it('shows loading state', () => {
    (useSatelliteStore as any).mockReturnValue({
      threats: [],
      fetchThreats: vi.fn(),
      loading: true,
      error: null,
    });
    
    render(<ThreatDashboard />);
    expect(screen.getByText(/loading/i)).toBeInTheDocument();
  });

  it('shows error state', () => {
    (useSatelliteStore as any).mockReturnValue({
      threats: [],
      fetchThreats: vi.fn(),
      loading: false,
      error: 'Failed to fetch threats',
    });
    
    render(<ThreatDashboard />);
    expect(screen.getByText(/error|failed/i)).toBeInTheDocument();
  });

  it('allows filtering by classification', async () => {
    render(<ThreatDashboard />);
    
    const filterButton = screen.getByRole('button', { name: /filter/i });
    fireEvent.click(filterButton);
    
    await waitFor(() => {
      expect(screen.getByText(/hostile/i)).toBeInTheDocument();
    });
  });

  it('fetches threats on mount', () => {
    const fetchThreats = vi.fn();
    (useSatelliteStore as any).mockReturnValue({
      threats: mockThreats,
      fetchThreats,
      loading: false,
      error: null,
    });
    
    render(<ThreatDashboard />);
    expect(fetchThreats).toHaveBeenCalled();
  });

  it('displays threat details on row click', async () => {
    render(<ThreatDashboard />);
    
    const threatRow = screen.getByText('COSMOS 2542');
    fireEvent.click(threatRow);
    
    await waitFor(() => {
      expect(screen.getByText(/43013/)).toBeInTheDocument();
    });
  });
});
