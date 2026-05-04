import { useState } from 'react'
import { RunOverrides } from '../api/client'

interface Props {
  projectName: string
  onRun: (overrides: RunOverrides) => void
  onClose: () => void
}

const ALL_CATEGORIES = ['functional', 'visual', 'security']

export function RunConfigModal({ projectName, onRun, onClose }: Props) {
  const [username, setUsername] = useState('')
  const [password, setPassword] = useState('')
  const [hintsText, setHintsText] = useState('')
  const [categories, setCategories] = useState<string[]>(ALL_CATEGORIES)

  function toggleCategory(cat: string) {
    setCategories(prev =>
      prev.includes(cat) ? prev.filter(c => c !== cat) : [...prev, cat]
    )
  }

  function handleSubmit(e: React.FormEvent) {
    e.preventDefault()
    const overrides: RunOverrides = {}
    if (username.trim()) overrides.username = username.trim()
    if (password) overrides.password = password
    const hints = hintsText.split('\n').map(h => h.trim()).filter(Boolean)
    if (hints.length) overrides.hints = hints
    if (categories.length !== ALL_CATEGORIES.length) overrides.categories = categories
    onRun(overrides)
  }

  return (
    <div className="fixed inset-0 bg-black/50 flex items-center justify-center z-50">
      <div className="bg-white rounded-xl shadow-xl w-full max-w-lg p-6">
        <h2 className="text-xl font-semibold mb-1">Run Configuration</h2>
        <p className="text-sm text-gray-500 mb-5">
          Project: <span className="font-medium text-gray-700">{projectName}</span>
          <span className="ml-2 text-xs text-gray-400">(all fields optional)</span>
        </p>

        <form onSubmit={handleSubmit} className="space-y-4">
          {/* Credentials */}
          <fieldset className="border border-gray-200 rounded-lg p-4">
            <legend className="text-sm font-medium text-gray-600 px-1">Authentication</legend>
            <div className="space-y-3 mt-1">
              <div>
                <label className="block text-sm text-gray-700 mb-1">Username / Email</label>
                <input
                  className="w-full border border-gray-300 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-green-500"
                  placeholder="user@example.com"
                  value={username}
                  onChange={e => setUsername(e.target.value)}
                  autoComplete="username"
                />
              </div>
              <div>
                <label className="block text-sm text-gray-700 mb-1">Password</label>
                <input
                  type="password"
                  className="w-full border border-gray-300 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-green-500"
                  placeholder="••••••••"
                  value={password}
                  onChange={e => setPassword(e.target.value)}
                  autoComplete="current-password"
                />
              </div>
            </div>
          </fieldset>

          {/* Categories */}
          <div>
            <label className="block text-sm font-medium text-gray-700 mb-2">Test Categories</label>
            <div className="flex gap-3">
              {ALL_CATEGORIES.map(cat => (
                <label key={cat} className="flex items-center gap-1.5 cursor-pointer">
                  <input
                    type="checkbox"
                    checked={categories.includes(cat)}
                    onChange={() => toggleCategory(cat)}
                    className="accent-green-600"
                  />
                  <span className="text-sm capitalize">{cat}</span>
                </label>
              ))}
            </div>
          </div>

          {/* Extra hints */}
          <div>
            <label className="block text-sm font-medium text-gray-700 mb-1">
              Extra Hints <span className="text-gray-400 font-normal">(one per line)</span>
            </label>
            <textarea
              className="w-full border border-gray-300 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-green-500 resize-none"
              rows={3}
              placeholder={"Focus on checkout flow\nTest search with special characters"}
              value={hintsText}
              onChange={e => setHintsText(e.target.value)}
            />
          </div>

          <div className="flex gap-2 justify-end pt-1">
            <button
              type="button"
              onClick={onClose}
              className="px-4 py-2 text-sm rounded-lg border border-gray-300 hover:bg-gray-50"
            >
              Cancel
            </button>
            <button
              type="submit"
              disabled={categories.length === 0}
              className="px-5 py-2 text-sm rounded-lg bg-green-600 text-white hover:bg-green-700 disabled:opacity-50"
            >
              Run Now
            </button>
          </div>
        </form>
      </div>
    </div>
  )
}
