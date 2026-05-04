import { Link } from 'react-router-dom'
import { api, RunRecord } from '../api/client'

interface Props {
  projectName: string
  runs: RunRecord[]
}

export function RunHistoryTable({ projectName, runs }: Props) {
  if (runs.length === 0) {
    return <p className="text-gray-500 text-sm py-4">No runs yet for this project.</p>
  }

  return (
    <div className="overflow-x-auto">
      <table className="w-full text-sm">
        <thead>
          <tr className="text-left text-gray-500 border-b border-gray-200">
            <th className="pb-2 font-medium">Run ID</th>
            <th className="pb-2 font-medium">Date</th>
            <th className="pb-2 font-medium">Duration</th>
            <th className="pb-2 font-medium text-right">Total</th>
            <th className="pb-2 font-medium text-right">Passed</th>
            <th className="pb-2 font-medium text-right">Failed</th>
            <th className="pb-2 font-medium text-right">Actions</th>
          </tr>
        </thead>
        <tbody>
          {runs.map(r => (
            <tr key={r.run_id} className="border-b border-gray-100 hover:bg-gray-50">
              <td className="py-2 font-mono text-xs text-gray-600">{r.run_id}</td>
              <td className="py-2 text-gray-600">
                {r.completed_at ? r.completed_at.slice(0, 16).replace('T', ' ') : '—'}
              </td>
              <td className="py-2 text-gray-600">
                {r.duration_seconds != null ? `${Math.round(r.duration_seconds)}s` : '—'}
              </td>
              <td className="py-2 text-right">{r.total_tests ?? '—'}</td>
              <td className="py-2 text-right text-green-600 font-medium">{r.passed ?? '—'}</td>
              <td className="py-2 text-right text-red-500 font-medium">{r.failed ?? '—'}</td>
              <td className="py-2 text-right">
                <div className="flex items-center justify-end gap-3">
                  <Link
                    to={`/projects/${projectName}/runs/${r.run_id}`}
                    className="text-blue-600 hover:underline"
                  >
                    Details
                  </Link>
                  <Link
                    to={`/projects/${projectName}/reports/${r.run_id}`}
                    className="text-gray-500 hover:underline"
                  >
                    Report
                  </Link>
                  <a
                    href={api.exportXlsxUrl(projectName, r.run_id)}
                    download
                    className="text-emerald-600 hover:underline"
                  >
                    Excel
                  </a>
                </div>
              </td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  )
}
