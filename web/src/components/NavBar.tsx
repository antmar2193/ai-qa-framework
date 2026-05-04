import { Link } from 'react-router-dom'

export function NavBar() {
  return (
    <nav className="bg-gray-900 text-white px-6 py-3 flex items-center gap-4 shadow">
      <Link to="/" className="font-bold text-lg tracking-tight hover:text-green-400 transition-colors">
        QA Framework
      </Link>
      <span className="text-gray-500 text-sm">Autonomous Website Testing</span>
    </nav>
  )
}
