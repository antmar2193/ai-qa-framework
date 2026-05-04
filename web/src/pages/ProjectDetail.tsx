import { useEffect, useCallback, useState } from 'react'
import { Link, useParams } from 'react-router-dom'
import { api, RunRecord, RunOverrides } from '../api/client'
import { RunHistoryTable } from '../components/RunHistoryTable'
import { LiveLogPanel } from '../components/LiveLogPanel'
import { RunConfigModal } from '../components/RunConfigModal'

export function ProjectDetail() {
  const { name } = useParams<{ name: string }>()
  const [runs, setRuns] = useState<RunRecord[]>([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)
  const [activeRunId, setActiveRunId] = useState<string | null>(null)
  const [runResult, setRunResult] = useState<{ status: string } | null>(null)
  const [runError, setRunError] = useState<string | null>(null)
  const [showConfig, setShowConfig] = useState(false)

  const loadRuns = useCallback(async () => {
    if (!name) return
    try {
      const data = await api.listRuns(name)
      setRuns(data)
    } catch (err: unknown) {
      setError(err instanceof Error ? err.message : 'Failed to load runs')
    } finally {
      setLoading(false)
    }
  }, [name])

  useEffect(() => { loadRuns() }, [loadRuns])

  async function handleRun(overrides: RunOverrides) {
    if (!name) return
    setShowConfig(false)
    setRunError(null)
    setRunResult(null)
    try {
      const { run_id } = await api.triggerRun(name, overrides)
      setActiveRunId(run_id)
    } catch (err: unknown) {
      setRunError(err instanceof Error ? err.message : 'Failed to start run')
    }
  }

  function handleRunDone(status: string) {
    setRunResult({ status })
    setActiveRunId(null)
    loadRuns()
  }

  if (!name) return null

  return (
    <div className="max-w-4xl mx-auto py-8 px-4">
      {showConfig && (
        <RunConfigModal
          projectName={name}
          onRun={handleRun}
          onClose={() => setShowConfig(false)}
        />
      )}

      <div className="mb-4">
        <Link to="/" className="text-sm text-gray-500 hover:text-gray-700">← All Projects</Link>
      </div>

      <div className="flex items-center justify-between mb-6">
        <h1 className="text-2xl font-bold text-gray-900">{name}</h1>
        <button
          onClick={() => setShowConfig(true)}
          disabled={!!activeRunId}
          className="bg-green-600 text-white px-5 py-2 rounded-lg text-sm font-medium hover:bg-green-700 disabled:opacity-50"
        >
          {activeRunId ? 'Running…' : 'Run Now'}
        </button>
      </div>

      {runError && (
        <div className="mb-4 p-3 bg-red-50 border border-red-200 rounded-lg text-red-700 text-sm">
          {runError}
        </div>
      )}

      {runResult && (
        <div
          className={`mb-4 p-3 rounded-lg text-sm font-medium ${
            runResult.status === 'passed'
              ? 'bg-green-50 border border-green-200 text-green-700'
              : 'bg-red-50 border border-red-200 text-red-700'
          }`}
        >
          Run {runResult.status === 'passed' ? 'passed ✓' : 'failed ✗'}
        </div>
      )}

      {activeRunId && (
        <LiveLogPanel
          projectName={name}
          runId={activeRunId}
          onDone={handleRunDone}
        />
      )}

      <div className="mt-8 bg-white rounded-xl shadow-sm border border-gray-200 p-6">
        <h2 className="text-lg font-semibold mb-4">Run History</h2>
        {loading ? (
          <div className="space-y-2">
            {[1, 2].map(i => <div key={i} className="h-8 bg-gray-100 rounded animate-pulse" />)}
          </div>
        ) : error ? (
          <p className="text-red-600 text-sm">{error}</p>
        ) : (
          <RunHistoryTable projectName={name} runs={runs} />
        )}
      </div>
    </div>
  )
}
