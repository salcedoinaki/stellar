import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { render, screen, fireEvent, waitFor } from '@testing-library/react';
import { OrbitalViewer } from './OrbitalViewer';

// Mock Three.js and related libraries
vi.mock('three', () => ({
  Scene: vi.fn().mockImplementation(() => ({
    add: vi.fn(),
    remove: vi.fn(),
    background: null,
  })),
  PerspectiveCamera: vi.fn().mockImplementation(() => ({
    position: { set: vi.fn(), copy: vi.fn() },
    lookAt: vi.fn(),
    updateProjectionMatrix: vi.fn(),
  })),
  WebGLRenderer: vi.fn().mockImplementation(() => ({
    setSize: vi.fn(),
    setPixelRatio: vi.fn(),
    render: vi.fn(),
    dispose: vi.fn(),
    domElement: document.createElement('canvas'),
  })),
  SphereGeometry: vi.fn(),
  MeshBasicMaterial: vi.fn(),
  MeshPhongMaterial: vi.fn(),
  Mesh: vi.fn().mockImplementation(() => ({
    position: { set: vi.fn(), x: 0, y: 0, z: 0 },
    rotation: { x: 0, y: 0, z: 0 },
  })),
  LineBasicMaterial: vi.fn(),
  BufferGeometry: vi.fn().mockImplementation(() => ({
    setFromPoints: vi.fn(),
  })),
  Line: vi.fn().mockImplementation(() => ({
    position: { set: vi.fn() },
  })),
  Vector3: vi.fn().mockImplementation((x, y, z) => ({ x, y, z })),
  Color: vi.fn(),
  AmbientLight: vi.fn(),
  PointLight: vi.fn().mockImplementation(() => ({
    position: { set: vi.fn() },
  })),
  TextureLoader: vi.fn().mockImplementation(() => ({
    load: vi.fn(),
  })),
  Group: vi.fn().mockImplementation(() => ({
    add: vi.fn(),
    remove: vi.fn(),
    children: [],
  })),
  Raycaster: vi.fn().mockImplementation(() => ({
    setFromCamera: vi.fn(),
    intersectObjects: vi.fn().mockReturnValue([]),
  })),
  Vector2: vi.fn().mockImplementation((x, y) => ({ x, y })),
}));

vi.mock('three/examples/jsm/controls/OrbitControls', () => ({
  OrbitControls: vi.fn().mockImplementation(() => ({
    enableDamping: true,
    dampingFactor: 0.05,
    update: vi.fn(),
    dispose: vi.fn(),
  })),
}));

const mockSatellites = [
  {
    id: 'sat-1',
    norad_id: 25544,
    name: 'ISS (ZARYA)',
    position: { x: 6771, y: 0, z: 0 },
    velocity: { x: 0, y: 7.66, z: 0 },
    orbit_type: 'LEO',
  },
  {
    id: 'sat-2',
    norad_id: 43013,
    name: 'COSMOS 2542',
    position: { x: 7000, y: 1000, z: 500 },
    velocity: { x: -0.5, y: 7.5, z: 0.1 },
    orbit_type: 'LEO',
  },
];

const mockConjunction = {
  id: 'conj-1',
  primary_id: 'sat-1',
  secondary_id: 'sat-2',
  tca: '2026-01-24T14:30:00Z',
  miss_distance_km: 0.5,
  probability_of_collision: 0.0001,
};

describe('OrbitalViewer', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    // Mock requestAnimationFrame
    vi.spyOn(window, 'requestAnimationFrame').mockImplementation((cb) => {
      return 1;
    });
  });

  afterEach(() => {
    vi.restoreAllMocks();
  });

  it('renders the canvas container', () => {
    render(<OrbitalViewer satellites={mockSatellites} />);
    expect(screen.getByTestId('orbital-viewer')).toBeInTheDocument();
  });

  it('displays satellite count', () => {
    render(<OrbitalViewer satellites={mockSatellites} />);
    expect(screen.getByText(/2.*satellites|objects/i)).toBeInTheDocument();
  });

  it('shows satellite list panel', () => {
    render(<OrbitalViewer satellites={mockSatellites} showList />);
    expect(screen.getByText('ISS (ZARYA)')).toBeInTheDocument();
    expect(screen.getByText('COSMOS 2542')).toBeInTheDocument();
  });

  it('highlights selected satellite', async () => {
    render(<OrbitalViewer satellites={mockSatellites} showList />);
    
    const satellite = screen.getByText('ISS (ZARYA)');
    fireEvent.click(satellite);
    
    await waitFor(() => {
      expect(satellite.closest('li')).toHaveClass('selected');
    });
  });

  it('displays conjunction warning', () => {
    render(
      <OrbitalViewer
        satellites={mockSatellites}
        conjunction={mockConjunction}
      />
    );
    
    expect(screen.getByText(/conjunction|warning/i)).toBeInTheDocument();
  });

  it('shows TCA countdown', () => {
    render(
      <OrbitalViewer
        satellites={mockSatellites}
        conjunction={mockConjunction}
      />
    );
    
    expect(screen.getByText(/tca|time.*closest/i)).toBeInTheDocument();
  });

  it('provides zoom controls', () => {
    render(<OrbitalViewer satellites={mockSatellites} />);
    
    expect(screen.getByRole('button', { name: /zoom.*in|\+/i })).toBeInTheDocument();
    expect(screen.getByRole('button', { name: /zoom.*out|-/i })).toBeInTheDocument();
  });

  it('toggles orbit visibility', async () => {
    render(<OrbitalViewer satellites={mockSatellites} />);
    
    const toggleOrbits = screen.getByRole('button', { name: /orbit|toggle/i });
    fireEvent.click(toggleOrbits);
    
    await waitFor(() => {
      expect(toggleOrbits).toHaveAttribute('aria-pressed', 'false');
    });
  });

  it('switches view modes', async () => {
    render(<OrbitalViewer satellites={mockSatellites} />);
    
    const viewModeButton = screen.getByRole('button', { name: /view|mode|2d|3d/i });
    fireEvent.click(viewModeButton);
    
    await waitFor(() => {
      expect(screen.getByText(/2d|top.*view/i)).toBeInTheDocument();
    });
  });

  it('displays time controls', () => {
    render(<OrbitalViewer satellites={mockSatellites} showTimeControls />);
    
    expect(screen.getByRole('button', { name: /play|pause/i })).toBeInTheDocument();
    expect(screen.getByRole('slider', { name: /speed|time/i })).toBeInTheDocument();
  });

  it('handles empty satellite list', () => {
    render(<OrbitalViewer satellites={[]} />);
    
    expect(screen.getByText(/no.*satellites|empty/i)).toBeInTheDocument();
  });

  it('shows loading state', () => {
    render(<OrbitalViewer satellites={[]} loading />);
    
    expect(screen.getByText(/loading/i)).toBeInTheDocument();
  });

  it('focuses on specific satellite', async () => {
    const onFocus = vi.fn();
    render(
      <OrbitalViewer
        satellites={mockSatellites}
        showList
        onSatelliteFocus={onFocus}
      />
    );
    
    const focusButton = screen.getAllByRole('button', { name: /focus|center/i })[0];
    fireEvent.click(focusButton);
    
    expect(onFocus).toHaveBeenCalledWith('sat-1');
  });

  it('renders trajectory preview for COA', () => {
    const mockCOA = {
      id: 'coa-1',
      trajectory: [
        { x: 6771, y: 0, z: 0, t: 0 },
        { x: 6775, y: 100, z: 50, t: 60 },
        { x: 6780, y: 200, z: 100, t: 120 },
      ],
    };
    
    render(
      <OrbitalViewer
        satellites={mockSatellites}
        conjunction={mockConjunction}
        selectedCOA={mockCOA}
      />
    );
    
    expect(screen.getByText(/trajectory|maneuver/i)).toBeInTheDocument();
  });

  it('cleans up on unmount', () => {
    const { unmount } = render(<OrbitalViewer satellites={mockSatellites} />);
    
    // Should not throw during cleanup
    expect(() => unmount()).not.toThrow();
  });
});
