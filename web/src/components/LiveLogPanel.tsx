import { useEffect, useRef, useState } from 'react'

interface Props {
  projectName: string
  runId: string
  onDone: (status: string) => void
}

export function LiveLogPanel({ projectName, runId, onDone }: Props) {
  const [lines, setLines] = useState<string[]>([])
  const [connected, setConnected] = useState(true)
  const bottomRef = useRef<HTMLDivElement>(null)

  useEffect(() => {
    const es = new EventSource(`/api/projects/${projectName}/run/${runId}/stream`)

    es.onmessage = (event) => {
      const raw: string = event.data
      // Check for done event
      try {
        const parsed = JSON.parse(raw)
        if (parsed.event === 'done') {
          es.close()
          setConnected(false)
          onDone(parsed.status)
          return
        }
      } catch {
        // Not JSON — it's a plain log line
      }
      setLines(prev => [...prev, raw])
    }

    es.onerror = () => {
      es.close()
      setConnected(false)
      setLines(prev => [...prev, '⚠ Connection lost — refresh to retry'])
    }

    return () => es.close()
  }, [projectName, runId, onDone])

  // Auto-scroll to bottom
  useEffect(() => {
    bottomRef.current?.scrollIntoView({ behavior: 'smooth' })
  }, [lines])

  return (
    <div className="mt-4 rounded-xl border border-gray-200 bg-gray-950 text-green-400 font-mono text-xs">
      <div className="flex items-center gap-2 px-3 py-2 border-b border-gray-800">
        <span className="text-gray-400">Live Log</span>
        {connected && (
          <span className="flex items-center gap-1 text-green-400">
            <span className="w-2 h-2 rounded-full bg-green-400 animate-pulse inline-block" />
            Live
          </span>
        )}
      </div>
      <div className="h-64 overflow-y-auto p-3 space-y-0.5">
        {lines.map((line, i) => (
          <div key={i}>{line}</div>
        ))}
        <div ref={bottomRef} />
      </div>
    </div>
  )
}
