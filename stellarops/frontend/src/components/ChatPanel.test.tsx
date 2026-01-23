import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { render, screen, fireEvent, waitFor } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { ChatPanel } from './ChatPanel';

// Mock WebSocket
class MockWebSocket {
  static OPEN = 1;
  static CLOSED = 3;
  
  readyState = MockWebSocket.OPEN;
  onopen: (() => void) | null = null;
  onmessage: ((event: MessageEvent) => void) | null = null;
  onclose: (() => void) | null = null;
  onerror: ((error: Event) => void) | null = null;
  
  send = vi.fn();
  close = vi.fn();
  
  constructor(url: string) {
    setTimeout(() => this.onopen?.(), 0);
  }
  
  simulateMessage(data: any) {
    this.onmessage?.({ data: JSON.stringify(data) } as MessageEvent);
  }
}

// Mock fetch for API calls
global.fetch = vi.fn();

describe('ChatPanel', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    (global.fetch as any).mockResolvedValue({
      ok: true,
      json: () => Promise.resolve({ response: 'AI response' }),
    });
  });

  afterEach(() => {
    vi.restoreAllMocks();
  });

  it('renders chat input', () => {
    render(<ChatPanel />);
    expect(screen.getByPlaceholderText(/message|ask|type/i)).toBeInTheDocument();
  });

  it('renders send button', () => {
    render(<ChatPanel />);
    expect(screen.getByRole('button', { name: /send/i })).toBeInTheDocument();
  });

  it('displays welcome message', () => {
    render(<ChatPanel />);
    expect(screen.getByText(/hello|welcome|help|assistant/i)).toBeInTheDocument();
  });

  it('sends message on button click', async () => {
    render(<ChatPanel />);
    
    const input = screen.getByPlaceholderText(/message|ask|type/i);
    const sendButton = screen.getByRole('button', { name: /send/i });
    
    await userEvent.type(input, 'What is the ISS orbit?');
    fireEvent.click(sendButton);
    
    await waitFor(() => {
      expect(screen.getByText('What is the ISS orbit?')).toBeInTheDocument();
    });
  });

  it('sends message on Enter key', async () => {
    render(<ChatPanel />);
    
    const input = screen.getByPlaceholderText(/message|ask|type/i);
    
    await userEvent.type(input, 'List all conjunctions{enter}');
    
    await waitFor(() => {
      expect(screen.getByText(/list all conjunctions/i)).toBeInTheDocument();
    });
  });

  it('clears input after sending', async () => {
    render(<ChatPanel />);
    
    const input = screen.getByPlaceholderText(/message|ask|type/i) as HTMLInputElement;
    
    await userEvent.type(input, 'Test message');
    fireEvent.click(screen.getByRole('button', { name: /send/i }));
    
    await waitFor(() => {
      expect(input.value).toBe('');
    });
  });

  it('shows loading indicator while waiting for response', async () => {
    (global.fetch as any).mockImplementation(() => 
      new Promise(resolve => setTimeout(() => resolve({
        ok: true,
        json: () => Promise.resolve({ response: 'Response' }),
      }), 1000))
    );
    
    render(<ChatPanel />);
    
    const input = screen.getByPlaceholderText(/message|ask|type/i);
    await userEvent.type(input, 'Question');
    fireEvent.click(screen.getByRole('button', { name: /send/i }));
    
    expect(screen.getByText(/thinking|loading|typing/i)).toBeInTheDocument();
  });

  it('displays AI response', async () => {
    (global.fetch as any).mockResolvedValue({
      ok: true,
      json: () => Promise.resolve({ response: 'The ISS orbits at 400km altitude.' }),
    });
    
    render(<ChatPanel />);
    
    const input = screen.getByPlaceholderText(/message|ask|type/i);
    await userEvent.type(input, 'ISS altitude?');
    fireEvent.click(screen.getByRole('button', { name: /send/i }));
    
    await waitFor(() => {
      expect(screen.getByText(/400km/i)).toBeInTheDocument();
    });
  });

  it('handles API error gracefully', async () => {
    (global.fetch as any).mockRejectedValue(new Error('Network error'));
    
    render(<ChatPanel />);
    
    const input = screen.getByPlaceholderText(/message|ask|type/i);
    await userEvent.type(input, 'Test');
    fireEvent.click(screen.getByRole('button', { name: /send/i }));
    
    await waitFor(() => {
      expect(screen.getByText(/error|failed|try again/i)).toBeInTheDocument();
    });
  });

  it('disables send button when input is empty', () => {
    render(<ChatPanel />);
    
    const sendButton = screen.getByRole('button', { name: /send/i });
    expect(sendButton).toBeDisabled();
  });

  it('enables send button when input has text', async () => {
    render(<ChatPanel />);
    
    const input = screen.getByPlaceholderText(/message|ask|type/i);
    const sendButton = screen.getByRole('button', { name: /send/i });
    
    await userEvent.type(input, 'Hello');
    
    expect(sendButton).toBeEnabled();
  });

  it('scrolls to bottom on new message', async () => {
    const scrollIntoViewMock = vi.fn();
    Element.prototype.scrollIntoView = scrollIntoViewMock;
    
    render(<ChatPanel />);
    
    const input = screen.getByPlaceholderText(/message|ask|type/i);
    await userEvent.type(input, 'Test');
    fireEvent.click(screen.getByRole('button', { name: /send/i }));
    
    await waitFor(() => {
      expect(scrollIntoViewMock).toHaveBeenCalled();
    });
  });

  it('shows suggested queries', () => {
    render(<ChatPanel showSuggestions />);
    
    expect(screen.getByText(/conjunction|satellite|orbit|threat/i)).toBeInTheDocument();
  });

  it('fills input with suggested query on click', async () => {
    render(<ChatPanel showSuggestions />);
    
    const suggestion = screen.getByText(/show.*conjunction|list.*threat/i);
    fireEvent.click(suggestion);
    
    const input = screen.getByPlaceholderText(/message|ask|type/i) as HTMLInputElement;
    expect(input.value).not.toBe('');
  });

  it('minimizes panel', async () => {
    render(<ChatPanel />);
    
    const minimizeButton = screen.getByRole('button', { name: /minimize|collapse/i });
    fireEvent.click(minimizeButton);
    
    await waitFor(() => {
      expect(screen.queryByPlaceholderText(/message|ask|type/i)).not.toBeVisible();
    });
  });

  it('preserves chat history', async () => {
    const { rerender } = render(<ChatPanel />);
    
    const input = screen.getByPlaceholderText(/message|ask|type/i);
    await userEvent.type(input, 'First message');
    fireEvent.click(screen.getByRole('button', { name: /send/i }));
    
    await waitFor(() => {
      expect(screen.getByText('First message')).toBeInTheDocument();
    });
    
    // Re-render component
    rerender(<ChatPanel />);
    
    // History should still be visible
    expect(screen.getByText('First message')).toBeInTheDocument();
  });

  it('clears chat history on request', async () => {
    render(<ChatPanel />);
    
    // Add a message first
    const input = screen.getByPlaceholderText(/message|ask|type/i);
    await userEvent.type(input, 'Test message');
    fireEvent.click(screen.getByRole('button', { name: /send/i }));
    
    await waitFor(() => {
      expect(screen.getByText('Test message')).toBeInTheDocument();
    });
    
    // Clear history
    const clearButton = screen.getByRole('button', { name: /clear|reset/i });
    fireEvent.click(clearButton);
    
    await waitFor(() => {
      expect(screen.queryByText('Test message')).not.toBeInTheDocument();
    });
  });
});
