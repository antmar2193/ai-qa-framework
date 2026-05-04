import { useEffect, useState } from 'react'
import { Link, useParams } from 'react-router-dom'
import { api, RunDetail as RunDetailType, TestResultDetail } from '../api/client'

function StatusBadge({ result }: { result: string }) {
  const colours: Record<string, string> = {
    pass: 'bg-green-100 text-green-700',
    fail: 'bg-red-100 text-red-700',
    skip: 'bg-gray-100 text-gray-600',
    error: 'bg-orange-100 text-orange-700',
  }
  return (
    <span className={`px-2 py-0.5 rounded-full text-xs font-medium ${colours[result] ?? 'bg-gray-100 text-gray-600'}`}>
      {result}
    </span>
  )
}

function TestCaseRow({ test, projectName, runId }: { test: TestResultDetail; projectName: string; runId: string }) {
  const [open, setOpen] = useState(false)
  const screenshots = test.evidence?.screenshots ?? []

  return (
    <>
      <tr
        className="border-b border-gray-100 hover:bg-gray-50 cursor-pointer"
        onClick={() => setOpen(o => !o)}
      >
        <td className="py-2 pr-4">
          <span className="mr-2 text-gray-400 text-xs">{open ? '▼' : '▶'}</span>
          {test.test_name}
        </td>
        <td className="py-2 text-xs text-gray-500 capitalize">{test.category}</td>
        <td className="py-2"><StatusBadge result={test.result} /></td>
        <td className="py-2 text-right text-gray-500 text-xs">
          {test.duration_seconds != null ? `${test.duration_seconds.toFixed(1)}s` : '—'}
        </td>
      </tr>
      {open && (
        <tr className="bg-gray-50">
          <td colSpan={4} className="px-4 py-3 text-sm space-y-3">
            {test.failure_reason && (
              <div className="text-red-600 font-mono text-xs bg-red-50 rounded p-2">
                {test.failure_reason}
              </div>
            )}
            {test.step_results && test.step_results.length > 0 && (
              <div>
                <p className="text-xs font-medium text-gray-500 mb-1">Steps</p>
                <ol className="space-y-1">
                  {test.step_results.map(s => (
                    <li key={s.step_index} className="flex gap-2 text-xs">
                      <span className={s.status === 'pass' ? 'text-green-600' : 'text-red-500'}>
                        {s.status === 'pass' ? '✓' : '✗'}
                      </span>
                      <span className="text-gray-600">{s.description}</span>
                      {s.error_message && (
                        <span className="text-red-500 italic">{s.error_message}</span>
                      )}
                    </li>
                  ))}
                </ol>
              </div>
            )}
            {screenshots.length > 0 && (
              <div>
                <p className="text-xs font-medium text-gray-500 mb-2">Screenshots</p>
                <div className="flex flex-wrap gap-2">
                  {screenshots.map((path, i) => {
                    const filename = path.split('/').pop() ?? path
                    const url = `/api/projects/${projectName}/runs/${runId}/evidence/${filename}`
                    return (
                      <a key={i} href={url} target="_blank" rel="noopener noreferrer">
                        <img
                          src={url}
                          alt={`screenshot ${i + 1}`}
                          className="h-24 w-auto rounded border border-gray-200 hover:opacity-80 object-cover"
                          onError={e => { (e.target as HTMLImageElement).style.display = 'none' }}
                        />
                      </a>
                    )
                  })}
                </div>
              </div>
            )}
            {test.evidence?.video_path && (
              <div>
                <p className="text-xs font-medium text-gray-500 mb-2">Video</p>
                <video
                  controls
                  className="max-w-lg rounded border border-gray-200"
                  src={`/api/projects/${projectName}/runs/${runId}/evidence/${test.evidence.video_path.split('/').pop()}`}
                />
              </div>
            )}
          </td>
        </tr>
      )}
    </>
  )
}

export function RunDetail() {
  const { name, runId } = useParams<{ name: string; runId: string }>()
  const [detail, setDetail] = useState<RunDetailType | null>(null)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)

  useEffect(() => {
    if (!name || !runId) return
    api.getRunDetail(name, runId)
      .then(setDetail)
      .catch(err => setError(err instanceof Error ? err.message : 'Failed to load run'))
      .finally(() => setLoading(false))
  }, [name, runId])

  if (!name || !runId) return null

  if (loading) {
    return (
      <div className="max-w-5xl mx-auto py-8 px-4 space-y-4">
        {[1, 2, 3].map(i => <div key={i} className="h-10 bg-gray-100 rounded animate-pulse" />)}
      </div>
    )
  }

  if (error) {
    return (
      <div className="max-w-5xl mx-auto py-8 px-4">
        <p className="text-red-600">{error}</p>
      </div>
    )
  }

  if (!detail) return null

  const passRate = detail.total_tests > 0
    ? Math.round((detail.passed / detail.total_tests) * 100)
    : 0

  return (
    <div className="max-w-5xl mx-auto py-8 px-4">
      <div className="mb-4 flex items-center gap-2 text-sm text-gray-500">
        <Link to="/" className="hover:text-gray-700">Projects</Link>
        <span>/</span>
        <Link to={`/projects/${name}`} className="hover:text-gray-700">{name}</Link>
        <span>/</span>
        <span className="text-gray-700 font-mono text-xs">{runId}</span>
      </div>

      {/* Summary cards */}
      <div className="grid grid-cols-2 sm:grid-cols-4 gap-4 mb-6">
        {[
          { label: 'Total', value: detail.total_tests, colour: 'text-gray-700' },
          { label: 'Passed', value: detail.passed, colour: 'text-green-600' },
          { label: 'Failed', value: detail.failed, colour: 'text-red-500' },
          { label: 'Pass rate', value: `${passRate}%`, colour: passRate >= 80 ? 'text-green-600' : 'text-red-500' },
        ].map(c => (
          <div key={c.label} className="bg-white rounded-xl shadow-sm border border-gray-200 p-4 text-center">
            <p className={`text-2xl font-bold ${c.colour}`}>{c.value}</p>
            <p className="text-xs text-gray-500 mt-1">{c.label}</p>
          </div>
        ))}
      </div>

      {/* Metadata + Export */}
      <div className="bg-white rounded-xl shadow-sm border border-gray-200 p-5 mb-6">
        <div className="flex items-center justify-between mb-3">
          <h2 className="text-sm font-semibold text-gray-700">Run Information</h2>
          <a
            href={api.exportXlsxUrl(name, runId)}
            download
            className="text-xs px-3 py-1.5 rounded-lg bg-emerald-600 text-white hover:bg-emerald-700"
          >
            Export Excel
          </a>
        </div>
        <dl className="grid grid-cols-2 gap-x-8 gap-y-2 text-sm">
          <div><dt className="text-gray-500">Run ID</dt><dd className="font-mono text-xs">{detail.run_id}</dd></div>
          <div><dt className="text-gray-500">Target URL</dt><dd className="truncate">{detail.target_url}</dd></div>
          <div><dt className="text-gray-500">Started</dt><dd>{detail.started_at?.slice(0, 16).replace('T', ' ')}</dd></div>
          <div><dt className="text-gray-500">Duration</dt><dd>{Math.round(detail.duration_seconds)}s</dd></div>
          {detail.run_meta && (
            <>
              <div><dt className="text-gray-500">Categories</dt><dd className="capitalize">{detail.run_meta.categories?.join(', ')}</dd></div>
              <div><dt className="text-gray-500">AI Model</dt><dd className="font-mono text-xs">{detail.run_meta.ai_model}</dd></div>
              {detail.run_meta.auth_username && (
                <div><dt className="text-gray-500">Username</dt><dd>{detail.run_meta.auth_username}</dd></div>
              )}
              {detail.run_meta.hints_count > 0 && (
                <div><dt className="text-gray-500">Hints</dt><dd>{detail.run_meta.hints_count}</dd></div>
              )}
            </>
          )}
        </dl>
      </div>

      {/* AI Summary */}
      {detail.ai_summary && (
        <div className="bg-blue-50 border border-blue-200 rounded-xl p-4 mb-6 text-sm text-blue-800">
          <p className="font-medium mb-1">AI Summary</p>
          <p>{detail.ai_summary}</p>
        </div>
      )}

      {/* Test cases */}
      <div className="bg-white rounded-xl shadow-sm border border-gray-200 p-5">
        <h2 className="text-sm font-semibold text-gray-700 mb-4">
          Test Cases ({detail.test_results.length})
        </h2>
        {detail.test_results.length === 0 ? (
          <p className="text-gray-500 text-sm">No test results recorded.</p>
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full text-sm">
              <thead>
                <tr className="text-left text-gray-500 border-b border-gray-200">
                  <th className="pb-2 font-medium">Test</th>
                  <th className="pb-2 font-medium">Category</th>
                  <th className="pb-2 font-medium">Result</th>
                  <th className="pb-2 font-medium text-right">Duration</th>
                </tr>
              </thead>
              <tbody>
                {detail.test_results.map(t => (
                  <TestCaseRow
                    key={t.test_id}
                    test={t}
                    projectName={name}
                    runId={runId}
                  />
                ))}
              </tbody>
            </table>
          </div>
        )}
      </div>
    </div>
  )
}
