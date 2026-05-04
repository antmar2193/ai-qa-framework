# WEB-3 — React + Vite + Tailwind scaffold + projects dashboard

**Sprint:** 3
**Status:** done ✅
**Effort:** M
**Depends on:** WEB-1

## Description

Scaffold the React frontend under `web/` using Vite + Tailwind CSS. Implement the projects dashboard: a single page that lists all configured projects and lets users create a new one, delete an existing one, and set the active project.

## Acceptance Criteria

### Scaffold
- `web/` directory with `package.json`, `vite.config.ts`, `tailwind.config.js`, `tsconfig.json`.
- `npm run dev` starts the Vite dev server on port 5173 and proxies `/api/*` to `http://localhost:8000`.
- `npm run build` outputs a production build to `web/dist/`.
- `npm run lint` runs ESLint with no errors on the scaffolded code.

### Projects dashboard (`/`)
- Displays a card or table row for each project returned by `GET /api/projects`.
- Each row shows: project name, target URL, last run date (or "Never"), pass/fail count, active marker (highlighted if active).
- **Create project** button opens a modal with "Name" and "Target URL" fields; submitting calls `POST /api/projects` and refreshes the list.
- **Set active** button calls `POST /api/projects/{name}/use` and updates the active marker without a full page reload.
- **Delete** button shows a confirmation dialog before calling `DELETE /api/projects/{name}`.
- Error states: if the API returns an error, display a toast/banner with the message.
- Loading state: show a skeleton or spinner while the project list is fetching.

### Routing
- Use React Router v6. Route `/` → dashboard, `/projects/:name` → detail page (stub — implemented in WEB-4).
- A top navigation bar links to the dashboard and shows the app name "QA Framework".

### Design
- Tailwind utility classes throughout — no custom CSS files.
- Dark header bar, white content area, green/red badges for pass/fail counts.

## Technical scope

```
web/
├── package.json           (react, react-dom, react-router-dom, tailwindcss, vite, typescript)
├── vite.config.ts         (proxy /api → localhost:8000)
├── tailwind.config.js
├── tsconfig.json
├── index.html
└── src/
    ├── main.tsx
    ├── App.tsx            (router setup)
    ├── api/
    │   └── client.ts      (fetch wrappers for all /api/* endpoints)
    ├── pages/
    │   ├── Dashboard.tsx
    │   └── ProjectDetail.tsx   (stub)
    └── components/
        ├── ProjectCard.tsx
        ├── CreateProjectModal.tsx
        └── NavBar.tsx
```

- `web/dist/` is gitignored; CI builds it before integration tests.
- Node 20+ required; add to `CONTRIBUTING.md`.
