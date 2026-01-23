import { describe, it, expect, vi, beforeEach } from 'vitest';
import { render, screen, fireEvent, waitFor } from '@testing-library/react';
import { COACard } from './COACard';
import { COAList } from './COAList';

// Mock recharts
vi.mock('recharts', () => ({
  ResponsiveContainer: ({ children }: any) => <div>{children}</div>,
  LineChart: ({ children }: any) => <div data-testid="line-chart">{children}</div>,
  Line: () => null,
  XAxis: () => null,
  YAxis: () => null,
  Tooltip: () => null,
}));

const mockCOA = {
  id: 'coa-1',
  conjunction_id: 'conj-123',
  name: 'Maneuver Option A',
  type: 'prograde',
  delta_v: 2.5,
  delta_v_components: { x: 1.2, y: 1.8, z: 0.5 },
  fuel_cost_kg: 15.3,
  execution_time: '2026-01-24T14:30:00Z',
  probability_of_collision_after: 0.00001,
  risk_reduction_percent: 99.5,
  status: 'pending',
  score: 0.92,
  created_at: '2026-01-23T10:00:00Z',
};

describe('COACard', () => {
  const mockOnSelect = vi.fn();
  const mockOnReject = vi.fn();
  const mockOnSimulate = vi.fn();

  beforeEach(() => {
    vi.clearAllMocks();
  });

  it('renders COA name and type', () => {
    render(
      <COACard
        coa={mockCOA}
        onSelect={mockOnSelect}
        onReject={mockOnReject}
        onSimulate={mockOnSimulate}
      />
    );
    
    expect(screen.getByText('Maneuver Option A')).toBeInTheDocument();
    expect(screen.getByText(/prograde/i)).toBeInTheDocument();
  });

  it('displays delta-v information', () => {
    render(
      <COACard
        coa={mockCOA}
        onSelect={mockOnSelect}
        onReject={mockOnReject}
        onSimulate={mockOnSimulate}
      />
    );
    
    expect(screen.getByText(/2\.5/)).toBeInTheDocument();
    expect(screen.getByText(/m\/s/i)).toBeInTheDocument();
  });

  it('shows fuel cost', () => {
    render(
      <COACard
        coa={mockCOA}
        onSelect={mockOnSelect}
        onReject={mockOnReject}
        onSimulate={mockOnSimulate}
      />
    );
    
    expect(screen.getByText(/15\.3/)).toBeInTheDocument();
    expect(screen.getByText(/kg/i)).toBeInTheDocument();
  });

  it('displays risk reduction percentage', () => {
    render(
      <COACard
        coa={mockCOA}
        onSelect={mockOnSelect}
        onReject={mockOnReject}
        onSimulate={mockOnSimulate}
      />
    );
    
    expect(screen.getByText(/99\.5%/)).toBeInTheDocument();
  });

  it('shows execution time', () => {
    render(
      <COACard
        coa={mockCOA}
        onSelect={mockOnSelect}
        onReject={mockOnReject}
        onSimulate={mockOnSimulate}
      />
    );
    
    expect(screen.getByText(/2026-01-24/)).toBeInTheDocument();
  });

  it('calls onSelect when select button clicked', () => {
    render(
      <COACard
        coa={mockCOA}
        onSelect={mockOnSelect}
        onReject={mockOnReject}
        onSimulate={mockOnSimulate}
      />
    );
    
    const selectButton = screen.getByRole('button', { name: /select/i });
    fireEvent.click(selectButton);
    
    expect(mockOnSelect).toHaveBeenCalledWith(mockCOA.id);
  });

  it('calls onReject when reject button clicked', () => {
    render(
      <COACard
        coa={mockCOA}
        onSelect={mockOnSelect}
        onReject={mockOnReject}
        onSimulate={mockOnSimulate}
      />
    );
    
    const rejectButton = screen.getByRole('button', { name: /reject/i });
    fireEvent.click(rejectButton);
    
    expect(mockOnReject).toHaveBeenCalledWith(mockCOA.id);
  });

  it('calls onSimulate when simulate button clicked', () => {
    render(
      <COACard
        coa={mockCOA}
        onSelect={mockOnSelect}
        onReject={mockOnReject}
        onSimulate={mockOnSimulate}
      />
    );
    
    const simulateButton = screen.getByRole('button', { name: /simulate/i });
    fireEvent.click(simulateButton);
    
    expect(mockOnSimulate).toHaveBeenCalledWith(mockCOA.id);
  });

  it('displays score badge', () => {
    render(
      <COACard
        coa={mockCOA}
        onSelect={mockOnSelect}
        onReject={mockOnReject}
        onSimulate={mockOnSimulate}
      />
    );
    
    expect(screen.getByText(/92%|0\.92/)).toBeInTheDocument();
  });

  it('shows selected status', () => {
    const selectedCOA = { ...mockCOA, status: 'selected' };
    
    render(
      <COACard
        coa={selectedCOA}
        onSelect={mockOnSelect}
        onReject={mockOnReject}
        onSimulate={mockOnSimulate}
      />
    );
    
    expect(screen.getByText(/selected/i)).toBeInTheDocument();
  });

  it('disables actions for rejected COA', () => {
    const rejectedCOA = { ...mockCOA, status: 'rejected' };
    
    render(
      <COACard
        coa={rejectedCOA}
        onSelect={mockOnSelect}
        onReject={mockOnReject}
        onSimulate={mockOnSimulate}
      />
    );
    
    const selectButton = screen.getByRole('button', { name: /select/i });
    expect(selectButton).toBeDisabled();
  });
});

describe('COAList', () => {
  const mockCOAs = [
    mockCOA,
    {
      ...mockCOA,
      id: 'coa-2',
      name: 'Maneuver Option B',
      type: 'retrograde',
      delta_v: 3.1,
      score: 0.85,
    },
    {
      ...mockCOA,
      id: 'coa-3',
      name: 'No Action',
      type: 'none',
      delta_v: 0,
      score: 0.45,
    },
  ];

  const mockOnSelect = vi.fn();
  const mockOnReject = vi.fn();
  const mockOnSimulate = vi.fn();

  beforeEach(() => {
    vi.clearAllMocks();
  });

  it('renders all COAs in list', () => {
    render(
      <COAList
        coas={mockCOAs}
        onSelect={mockOnSelect}
        onReject={mockOnReject}
        onSimulate={mockOnSimulate}
      />
    );
    
    expect(screen.getByText('Maneuver Option A')).toBeInTheDocument();
    expect(screen.getByText('Maneuver Option B')).toBeInTheDocument();
    expect(screen.getByText('No Action')).toBeInTheDocument();
  });

  it('sorts COAs by score (highest first)', () => {
    render(
      <COAList
        coas={mockCOAs}
        onSelect={mockOnSelect}
        onReject={mockOnReject}
        onSimulate={mockOnSimulate}
      />
    );
    
    const cards = screen.getAllByTestId('coa-card');
    expect(cards[0]).toHaveTextContent('Maneuver Option A');
  });

  it('shows empty state when no COAs', () => {
    render(
      <COAList
        coas={[]}
        onSelect={mockOnSelect}
        onReject={mockOnReject}
        onSimulate={mockOnSimulate}
      />
    );
    
    expect(screen.getByText(/no.*available|generate/i)).toBeInTheDocument();
  });

  it('displays recommended badge on top COA', () => {
    render(
      <COAList
        coas={mockCOAs}
        onSelect={mockOnSelect}
        onReject={mockOnReject}
        onSimulate={mockOnSimulate}
      />
    );
    
    expect(screen.getByText(/recommended/i)).toBeInTheDocument();
  });

  it('filters COAs by type', async () => {
    render(
      <COAList
        coas={mockCOAs}
        onSelect={mockOnSelect}
        onReject={mockOnReject}
        onSimulate={mockOnSimulate}
      />
    );
    
    const filterSelect = screen.getByLabelText(/filter|type/i);
    fireEvent.change(filterSelect, { target: { value: 'prograde' } });
    
    await waitFor(() => {
      expect(screen.getByText('Maneuver Option A')).toBeInTheDocument();
      expect(screen.queryByText('Maneuver Option B')).not.toBeInTheDocument();
    });
  });

  it('expands COA details on click', async () => {
    render(
      <COAList
        coas={mockCOAs}
        onSelect={mockOnSelect}
        onReject={mockOnReject}
        onSimulate={mockOnSimulate}
      />
    );
    
    const firstCard = screen.getByText('Maneuver Option A');
    fireEvent.click(firstCard);
    
    await waitFor(() => {
      expect(screen.getByText(/delta.*components|x.*y.*z/i)).toBeInTheDocument();
    });
  });
});
