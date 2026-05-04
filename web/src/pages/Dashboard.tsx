import { useEffect, useState } from 'react'
import { Link } from 'react-router-dom'
import { api, ProjectSummary } from '../api/client'
import { CreateProjectModal } from '../components/CreateProjectModal'

export function Dashboard() {
  const [projects, setProjects] = useState<ProjectSummary[]>([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)
  const [showCreate, setShowCreate] = useState(false)
  const [actionError, setActionError] = useState<string | null>(null)

  async function load() {
    try {
      setError(null)
      const data = await api.listProjects()
      setProjects(data)
    } catch (err: unknown) {
      setError(err instanceof Error ? err.message : 'Failed to load projects')
    } finally {
      setLoading(false)
    }
  }

  useEffect(() => { load() }, [])

  async function handleSetActive(name: string) {
    setActionError(null)
    try {
      await api.useProject(name)
      await load()
    } catch (err: unknown) {
      setActionError(err instanceof Error ? err.message : 'Failed to set active')
    }
  }

  async function handleDelete(name: string) {
    if (!confirm(`Delete project '${name}' and all its run history?`)) return
    setActionError(null)
    try {
      await api.deleteProject(name)
      await load()
    } catch (err: unknown) {
      setActionError(err instanceof Error ? err.message : 'Failed to delete')
    }
  }

  return (
    <div className="max-w-4xl mx-auto py-8 px-4">
      <div className="flex items-center justify-between mb-6">
        <h1 className="text-2xl font-bold text-gray-900">Projects</h1>
        <button
          onClick={() => setShowCreate(true)}
          className="bg-green-600 text-white px-4 py-2 rounded-lg text-sm font-medium hover:bg-green-700"
        >
          + New Project
        </button>
      </div>

      {actionError && (
        <div className="mb-4 p-3 bg-red-50 border border-red-200 rounded-lg text-red-700 text-sm">
          {actionError}
        </div>
      )}

      {loading && (
        <div className="space-y-3">
          {[1, 2, 3].map(i => (
            <div key={i} className="h-20 bg-gray-100 rounded-xl animate-pulse" />
          ))}
        </div>
      )}

      {error && !loading && (
        <div className="p-4 bg-red-50 border border-red-200 rounded-xl text-red-700">{error}</div>
      )}

      {!loading && !error && projects.length === 0 && (
        <div className="text-center py-16 text-gray-500">
          <p className="text-lg mb-2">No projects yet</p>
          <p className="text-sm">Create your first project to get started.</p>
        </div>
      )}

      <div className="space-y-3">
        {projects.map(p => (
          <div
            key={p.name}
            className={`bg-white rounded-xl shadow-sm border p-4 flex items-center gap-4 ${
              p.active ? 'border-green-400' : 'border-gray-200'
            }`}
          >
            <div className="flex-1 min-w-0">
              <div className="flex items-center gap-2">
                <Link
                  to={`/projects/${p.name}`}
                  className="font-semibold text-gray-900 hover:text-green-700 truncate"
                >
                  {p.name}
                </Link>
                {p.active && (
                  <span className="text-xs bg-green-100 text-green-700 px-2 py-0.5 rounded-full font-medium">
                    active
                  </span>
                )}
              </div>
              <p className="text-sm text-gray-500 truncate">{p.target_url}</p>
            </div>

            <div className="text-right text-sm text-gray-500 shrink-0">
              {p.last_run_date ? (
                <>
                  <div>{p.last_run_date.slice(0, 10)}</div>
                  {p.last_run_stats && (
                    <div className="flex gap-2 justify-end mt-0.5">
                      <span className="text-green-600 font-medium">{p.last_run_stats.passed}✓</span>
                      <span className="text-red-500 font-medium">{p.last_run_stats.failed}✗</span>
                    </div>
                  )}
                </>
              ) : (
                <span>Never run</span>
              )}
            </div>

            <div className="flex gap-2 shrink-0">
              {!p.active && (
                <button
                  onClick={() => handleSetActive(p.name)}
                  className="text-xs px-3 py-1.5 border border-gray-300 rounded-lg hover:bg-gray-50"
                >
                  Set active
                </button>
              )}
              <button
                onClick={() => handleDelete(p.name)}
                className="text-xs px-3 py-1.5 border border-red-200 text-red-600 rounded-lg hover:bg-red-50"
              >
                Delete
              </button>
            </div>
          </div>
        ))}
      </div>

      {showCreate && (
        <CreateProjectModal
          onCreated={() => { setShowCreate(false); load() }}
          onClose={() => setShowCreate(false)}
        />
      )}
    </div>
  )
}
