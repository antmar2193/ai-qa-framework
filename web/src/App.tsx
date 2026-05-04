import { BrowserRouter, Route, Routes } from 'react-router-dom'
import { NavBar } from './components/NavBar'
import { Dashboard } from './pages/Dashboard'
import { ProjectDetail } from './pages/ProjectDetail'
import { ReportViewer } from './pages/ReportViewer'
import { RunDetail } from './pages/RunDetail'

function App() {
  return (
    <BrowserRouter>
      <Routes>
        {/* Report viewer: full-screen iframe, no nav bar */}
        <Route path="/projects/:name/reports/:runId" element={<ReportViewer />} />

        {/* All other pages share the nav bar layout */}
        <Route
          path="*"
          element={
            <div className="min-h-screen bg-gray-50">
              <NavBar />
              <main>
                <Routes>
                  <Route path="/" element={<Dashboard />} />
                  <Route path="/projects/:name" element={<ProjectDetail />} />
                  <Route path="/projects/:name/runs/:runId" element={<RunDetail />} />
                </Routes>
              </main>
            </div>
          }
        />
      </Routes>
    </BrowserRouter>
  )
}

export default App
