import { useState, useRef, useEffect, useCallback } from 'react'
import { api } from '../services/api'

interface ChatMessage {
  id: string
  role: 'user' | 'assistant' | 'system'
  content: string
  timestamp: Date
  intent?: string
  data?: Record<string, unknown>
}

interface QueryResponse {
  response: string
  intent: string
  confidence: number
  data?: Record<string, unknown>
}

export default function ChatPanel() {
  const [messages, setMessages] = useState<ChatMessage[]>([
    {
      id: 'welcome',
      role: 'system',
      content: 'Welcome to StellarOps Assistant. Ask me about satellites, threats, missions, or any operational questions.',
      timestamp: new Date(),
    },
  ])
  const [input, setInput] = useState('')
  const [isLoading, setIsLoading] = useState(false)
  const [isOpen, setIsOpen] = useState(false)
  const messagesEndRef = useRef<HTMLDivElement>(null)
  const inputRef = useRef<HTMLInputElement>(null)

  // Scroll to bottom on new messages
  useEffect(() => {
    messagesEndRef.current?.scrollIntoView({ behavior: 'smooth' })
  }, [messages])

  // Focus input when panel opens
  useEffect(() => {
    if (isOpen) {
      inputRef.current?.focus()
    }
  }, [isOpen])

  const sendMessage = useCallback(async () => {
    if (!input.trim() || isLoading) return

    const userMessage: ChatMessage = {
      id: `user-${Date.now()}`,
      role: 'user',
      content: input.trim(),
      timestamp: new Date(),
    }

    setMessages((prev) => [...prev, userMessage])
    setInput('')
    setIsLoading(true)

    try {
      // Process the query locally for common patterns
      const response = await processQuery(userMessage.content)
      
      const assistantMessage: ChatMessage = {
        id: `assistant-${Date.now()}`,
        role: 'assistant',
        content: response.response,
        timestamp: new Date(),
        intent: response.intent,
        data: response.data,
      }

      setMessages((prev) => [...prev, assistantMessage])
    } catch (error) {
      const errorMessage: ChatMessage = {
        id: `error-${Date.now()}`,
        role: 'assistant',
        content: `Sorry, I encountered an error: ${error instanceof Error ? error.message : 'Unknown error'}`,
        timestamp: new Date(),
      }
      setMessages((prev) => [...prev, errorMessage])
    } finally {
      setIsLoading(false)
    }
  }, [input, isLoading])

  // Handle keyboard
  const handleKeyDown = (e: React.KeyboardEvent) => {
    if (e.key === 'Enter' && !e.shiftKey) {
      e.preventDefault()
      sendMessage()
    }
  }

  // Suggested queries
  const suggestions = [
    'How many satellites are online?',
    'Show critical threats',
    'What missions are running?',
    'List active alarms',
    'Status of satellite fleet',
  ]

  return (
    <>
      {/* Toggle Button */}
      <button
        onClick={() => setIsOpen(!isOpen)}
        className={`fixed bottom-6 right-6 z-50 p-4 rounded-full shadow-lg transition-all ${
          isOpen
            ? 'bg-slate-700 text-slate-300'
            : 'bg-stellar-600 text-white hover:bg-stellar-500'
        }`}
      >
        {isOpen ? (
          <svg className="w-6 h-6" fill="none" viewBox="0 0 24 24" stroke="currentColor">
            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M6 18L18 6M6 6l12 12" />
          </svg>
        ) : (
          <svg className="w-6 h-6" fill="none" viewBox="0 0 24 24" stroke="currentColor">
            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M8 10h.01M12 10h.01M16 10h.01M9 16H5a2 2 0 01-2-2V6a2 2 0 012-2h14a2 2 0 012 2v8a2 2 0 01-2 2h-5l-5 5v-5z" />
          </svg>
        )}
      </button>

      {/* Chat Panel */}
      {isOpen && (
        <div className="fixed bottom-24 right-6 z-50 w-96 h-[500px] bg-slate-800 rounded-lg border border-slate-700 shadow-xl flex flex-col">
          {/* Header */}
          <div className="p-4 border-b border-slate-700 flex items-center justify-between">
            <div>
              <h3 className="text-white font-semibold">StellarOps Assistant</h3>
              <p className="text-xs text-slate-400">Natural language query interface</p>
            </div>
            <button
              onClick={() => setMessages(messages.slice(0, 1))}
              className="text-xs text-slate-400 hover:text-slate-200"
            >
              Clear
            </button>
          </div>

          {/* Messages */}
          <div className="flex-1 overflow-y-auto p-4 space-y-4">
            {messages.map((message) => (
              <div
                key={message.id}
                className={`flex ${message.role === 'user' ? 'justify-end' : 'justify-start'}`}
              >
                <div
                  className={`max-w-[80%] rounded-lg p-3 ${
                    message.role === 'user'
                      ? 'bg-stellar-600 text-white'
                      : message.role === 'system'
                      ? 'bg-slate-700/50 text-slate-300'
                      : 'bg-slate-700 text-slate-200'
                  }`}
                >
                  <p className="text-sm whitespace-pre-wrap">{message.content}</p>
                  {message.intent && (
                    <span className="text-xs text-slate-400 mt-1 block">
                      Intent: {message.intent}
                    </span>
                  )}
                  <span className="text-xs text-slate-500 mt-1 block">
                    {message.timestamp.toLocaleTimeString()}
                  </span>
                </div>
              </div>
            ))}
            {isLoading && (
              <div className="flex justify-start">
                <div className="bg-slate-700 rounded-lg p-3">
                  <div className="flex gap-1">
                    <span className="w-2 h-2 bg-slate-400 rounded-full animate-bounce" style={{ animationDelay: '0ms' }} />
                    <span className="w-2 h-2 bg-slate-400 rounded-full animate-bounce" style={{ animationDelay: '150ms' }} />
                    <span className="w-2 h-2 bg-slate-400 rounded-full animate-bounce" style={{ animationDelay: '300ms' }} />
                  </div>
                </div>
              </div>
            )}
            <div ref={messagesEndRef} />
          </div>

          {/* Suggestions */}
          {messages.length === 1 && (
            <div className="px-4 pb-2">
              <p className="text-xs text-slate-400 mb-2">Try asking:</p>
              <div className="flex flex-wrap gap-1">
                {suggestions.map((suggestion) => (
                  <button
                    key={suggestion}
                    onClick={() => setInput(suggestion)}
                    className="text-xs bg-slate-700 text-slate-300 px-2 py-1 rounded hover:bg-slate-600"
                  >
                    {suggestion}
                  </button>
                ))}
              </div>
            </div>
          )}

          {/* Input */}
          <div className="p-4 border-t border-slate-700">
            <div className="flex gap-2">
              <input
                ref={inputRef}
                type="text"
                value={input}
                onChange={(e) => setInput(e.target.value)}
                onKeyDown={handleKeyDown}
                placeholder="Ask about satellites, threats, missions..."
                disabled={isLoading}
                className="flex-1 bg-slate-700 text-slate-200 rounded-lg px-4 py-2 text-sm border border-slate-600 focus:border-stellar-500 focus:outline-none disabled:opacity-50"
              />
              <button
                onClick={sendMessage}
                disabled={!input.trim() || isLoading}
                className="px-4 py-2 bg-stellar-600 hover:bg-stellar-500 disabled:bg-slate-600 text-white rounded-lg transition-colors"
              >
                <svg className="w-5 h-5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M12 19l9 2-9-18-9 18 9-2zm0 0v-8" />
                </svg>
              </button>
            </div>
          </div>
        </div>
      )}
    </>
  )
}

// Local query processor (can be replaced with backend NLP)
async function processQuery(query: string): Promise<QueryResponse> {
  const lowercaseQuery = query.toLowerCase()

  // Satellite queries
  if (lowercaseQuery.includes('satellite') || lowercaseQuery.includes('fleet')) {
    try {
      const satellites = await api.satellites.list()
      const online = satellites.filter((s) => s.status === 'online' || s.mode !== 'critical').length
      const critical = satellites.filter((s) => s.mode === 'critical').length

      if (lowercaseQuery.includes('how many') || lowercaseQuery.includes('count')) {
        return {
          response: `There are ${satellites.length} satellites in the fleet. ${online} are online, ${critical} are in critical mode.`,
          intent: 'satellite_count',
          confidence: 0.9,
          data: { total: satellites.length, online, critical },
        }
      }

      if (lowercaseQuery.includes('status')) {
        const modes = satellites.reduce((acc, s) => {
          acc[s.mode] = (acc[s.mode] || 0) + 1
          return acc
        }, {} as Record<string, number>)
        
        return {
          response: `Fleet Status:\n• Nominal: ${modes.nominal || 0}\n• Safe: ${modes.safe || 0}\n• Critical: ${modes.critical || 0}\n• Standby: ${modes.standby || 0}`,
          intent: 'satellite_status',
          confidence: 0.85,
          data: { modes },
        }
      }

      return {
        response: `Found ${satellites.length} satellites. Use more specific queries like "satellite status" or "how many satellites are online".`,
        intent: 'satellite_query',
        confidence: 0.7,
      }
    } catch (error) {
      return {
        response: 'Unable to fetch satellite data. Please try again.',
        intent: 'error',
        confidence: 1,
      }
    }
  }

  // Threat/Conjunction queries
  if (lowercaseQuery.includes('threat') || lowercaseQuery.includes('conjunction') || lowercaseQuery.includes('collision')) {
    try {
      const conjunctions = await api.conjunctions.list()
      const critical = conjunctions.filter((c) => c.severity === 'critical').length
      const high = conjunctions.filter((c) => c.severity === 'high').length
      const active = conjunctions.filter((c) => c.status !== 'resolved' && c.status !== 'expired').length

      if (lowercaseQuery.includes('critical')) {
        return {
          response: `There are ${critical} critical threats requiring immediate attention.${critical > 0 ? ' Check the Threats dashboard for details.' : ''}`,
          intent: 'critical_threats',
          confidence: 0.9,
          data: { critical },
        }
      }

      return {
        response: `Current threat status:\n• Active conjunctions: ${active}\n• Critical: ${critical}\n• High priority: ${high}`,
        intent: 'threat_summary',
        confidence: 0.85,
        data: { active, critical, high },
      }
    } catch (error) {
      return {
        response: 'Unable to fetch threat data. Please try again.',
        intent: 'error',
        confidence: 1,
      }
    }
  }

  // Mission queries
  if (lowercaseQuery.includes('mission')) {
    try {
      const missions = await api.missions.list()
      const running = missions.filter((m) => m.status === 'running').length
      const pending = missions.filter((m) => m.status === 'pending').length
      const failed = missions.filter((m) => m.status === 'failed').length

      if (lowercaseQuery.includes('running') || lowercaseQuery.includes('active')) {
        return {
          response: `There are ${running} missions currently running.${running > 0 ? ' Check the Missions dashboard for details.' : ''}`,
          intent: 'running_missions',
          confidence: 0.9,
          data: { running },
        }
      }

      return {
        response: `Mission status:\n• Running: ${running}\n• Pending: ${pending}\n• Failed: ${failed}\n• Total: ${missions.length}`,
        intent: 'mission_summary',
        confidence: 0.85,
        data: { running, pending, failed, total: missions.length },
      }
    } catch (error) {
      return {
        response: 'Unable to fetch mission data. Please try again.',
        intent: 'error',
        confidence: 1,
      }
    }
  }

  // Alarm queries
  if (lowercaseQuery.includes('alarm') || lowercaseQuery.includes('alert')) {
    try {
      const alarms = await api.alarms.list()
      const active = alarms.filter((a) => a.status === 'active').length
      const critical = alarms.filter((a) => a.severity === 'critical' && a.status === 'active').length
      const unacknowledged = alarms.filter((a) => !a.acknowledged && a.status === 'active').length

      if (lowercaseQuery.includes('active')) {
        return {
          response: `There are ${active} active alarms, ${critical} of which are critical. ${unacknowledged} alarms need acknowledgment.`,
          intent: 'active_alarms',
          confidence: 0.9,
          data: { active, critical, unacknowledged },
        }
      }

      return {
        response: `Alarm status:\n• Active: ${active}\n• Critical: ${critical}\n• Unacknowledged: ${unacknowledged}`,
        intent: 'alarm_summary',
        confidence: 0.85,
        data: { active, critical, unacknowledged },
      }
    } catch (error) {
      return {
        response: 'Unable to fetch alarm data. Please try again.',
        intent: 'error',
        confidence: 1,
      }
    }
  }

  // Help
  if (lowercaseQuery.includes('help') || lowercaseQuery.includes('what can you')) {
    return {
      response: `I can help you with:\n• Satellite status and fleet information\n• Threat and conjunction monitoring\n• Mission status and tracking\n• Alarm management\n\nTry asking specific questions like "How many satellites are online?" or "Show critical threats".`,
      intent: 'help',
      confidence: 1,
    }
  }

  // Fallback
  return {
    response: `I'm not sure how to answer that. Try asking about:\n• Satellites (status, count)\n• Threats/Conjunctions\n• Missions\n• Alarms\n\nOr type "help" for more options.`,
    intent: 'unknown',
    confidence: 0.3,
  }
}
