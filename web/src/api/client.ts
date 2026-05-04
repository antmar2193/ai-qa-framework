export interface ProjectSummary {
  name: string
  target_url: string
  active: boolean
  last_run_date: string | null
  last_run_stats: { total: number; passed: number; failed: number } | null
}

export interface RunRecord {
  run_id: string
  completed_at?: string
  duration_seconds?: number
  total_tests?: number
  passed?: number
  failed?: number
}

export interface ReportFile {
  filename: string
  run_id: string
  modified_at: string
}

export interface StepResult {
  step_index: number
  action_type: string
  description: string
  status: string
  error_message?: string
  screenshot_path?: string
}

export interface TestResultDetail {
  test_id: string
  test_name: string
  category: string
  result: string
  duration_seconds: number
  failure_reason?: string
  step_results: StepResult[]
  evidence: { screenshots: string[]; video_path?: string }
}

export interface RunMeta {
  triggered_at: string
  target_url: string
  categories: string[]
  hints_count: number
  ai_model: string
  auth_username?: string
}

export interface RunDetail {
  run_id: string
  target_url: string
  started_at: string
  completed_at: string
  duration_seconds: number
  total_tests: number
  passed: number
  failed: number
  skipped: number
  errors: number
  ai_summary: string
  test_results: TestResultDetail[]
  run_meta?: RunMeta
}

export interface RunOverrides {
  username?: string
  password?: string
  hints?: string[]
  categories?: string[]
}

export interface RunStatus {
  run_id: string
  project: string
  status: 'running' | 'done' | 'passed' | 'failed'
  started_at: string
  completed_at: string | null
}

async function request<T>(path: string, init?: RequestInit): Promise<T> {
  const res = await fetch(path, init)
  if (!res.ok) {
    const body = await res.json().catch(() => ({ detail: res.statusText }))
    throw new Error(body.detail ?? res.statusText)
  }
  if (res.status === 204) return undefined as T
  return res.json()
}

export const api = {
  listProjects: () => request<ProjectSummary[]>('/api/projects'),

  createProject: (name: string, target_url: string) =>
    request<ProjectSummary>('/api/projects', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ name, target_url }),
    }),

  deleteProject: (name: string) =>
    request<void>(`/api/projects/${name}`, { method: 'DELETE' }),

  useProject: (name: string) =>
    request<{ active: string }>(`/api/projects/${name}/use`, { method: 'POST' }),

  listRuns: (name: string) => request<RunRecord[]>(`/api/projects/${name}/runs`),

  triggerRun: (name: string, overrides?: RunOverrides) =>
    request<{ run_id: string }>(`/api/projects/${name}/run`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(overrides ?? {}),
    }),

  runStatus: (name: string, runId: string) =>
    request<RunStatus>(`/api/projects/${name}/run/${runId}/status`),

  listReports: (name: string) => request<ReportFile[]>(`/api/projects/${name}/reports`),

  getRunDetail: (name: string, runId: string) =>
    request<RunDetail>(`/api/projects/${name}/runs/${runId}`),

  exportXlsxUrl: (name: string, runId: string) =>
    `/api/projects/${name}/runs/${runId}/export.xlsx`,
}
