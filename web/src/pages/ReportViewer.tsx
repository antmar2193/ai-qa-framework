import { Link, useParams } from 'react-router-dom'

export function ReportViewer() {
  const { name, runId } = useParams<{ name: string; runId: string }>()

  if (!name || !runId) return null

  const reportUrl = `/api/projects/${name}/reports/report_${runId}.html`

  return (
    <div className="flex flex-col h-screen">
      <div className="bg-gray-900 text-white px-4 py-2 flex items-center gap-4 shrink-0">
        <Link
          to={`/projects/${name}`}
          className="text-sm text-gray-300 hover:text-white"
        >
          ← {name}
        </Link>
        <span className="text-gray-500 text-sm">Report: {runId}</span>
      </div>
      <iframe
        src={reportUrl}
        title={`Report ${runId}`}
        className="flex-1 w-full border-0"
        onError={() => {}}
      />
    </div>
  )
}
