# AI QA Framework

[![License](https://img.shields.io/badge/License-Apache_2.0-blue.svg)](https://opensource.org/licenses/Apache-2.0)
[![CI](https://github.com/brentkastner/ai-qa-framework/actions/workflows/ci.yml/badge.svg)](https://github.com/brentkastner/ai-qa-framework/actions/workflows/ci.yml)
[![Python 3.12+](https://img.shields.io/badge/python-3.12+-blue.svg)](https://www.python.org/downloads/)

**Give it a URL. Get comprehensive test coverage.**

An autonomous AI-driven QA framework that automatically discovers, tests, and reports on any website — no manual test writing required.

```bash
pip install -r requirements.txt && playwright install chromium
export ANTHROPIC_API_KEY=your_key_here
python -m src.cli project create --name mysite --target https://yoursite.com
python -m src.cli run
```

**That's it.** The framework crawls your site, generates intelligent tests with Claude AI, executes them with smart error recovery, and produces detailed reports.

→ **[Read the full overview](./OVERVIEW.md)** to understand how it works and why it exists.

---

## What Makes This Different?

- **Zero test scripts** — AI generates tests by understanding your site
- **Self-healing** — When selectors break, AI analyzes screenshots and fixes them
- **Comprehensive coverage** — Functional, visual, and security testing in one pass
- **Natural language hints** — Guide priorities without writing test specs
- **Coverage memory** — Tracks what's been tested, focuses on gaps
- **Multi-project** — Manage and run tests for multiple sites from one installation

---

## Quick Start

### Option A: Local Python

**1. Install**

```bash
pip install -r requirements.txt
playwright install chromium
```

**2. Create a project**

```bash
export ANTHROPIC_API_KEY=your_key_here

# Create a named project for your site
python -m src.cli project create --name mysite --target https://yoursite.com

# Or import an existing qa-config.json
python -m src.cli project import --name mysite
```

**3. Run**

```bash
python -m src.cli run             # uses the active project automatically
open qa-reports/report_*.html    # macOS — or just open the HTML file
```

### Option B: Docker

No Python setup required — runs in a container with Playwright pre-installed.

```bash
# 1. Set your API key
echo "ANTHROPIC_API_KEY=your_key_here" > .env

# 2. Create your config (copy and edit the example)
cp qa-config.json.example qa-config.json

# 3. Run
docker compose run qa-framework run --config qa-config.json
```

Reports are written to `./qa-reports/`.

### Option C: Ollama (no API key)

```bash
# In qa-config.json set:
# "ai_provider": "ollama"
# "ai_model": "llama3.2"
python -m src.cli run
```

---

## Managing Multiple Projects

The framework stores named projects under `~/.qa-framework/` so you can manage several sites from one installation.

```bash
# Create projects
python -m src.cli project create --name kreitech --target https://kreitech.io
python -m src.cli project create --name myapp   --target https://myapp.com

# See all projects
python -m src.cli project list

# Switch active project
python -m src.cli project use kreitech

# Run the active project (no --project flag needed)
python -m src.cli run

# Or target a specific project explicitly
python -m src.cli run --project myapp

# View run history for a project
python -m src.cli project history kreitech

# Import an existing qa-config.json as a named project
python -m src.cli project import --name legacy --config path/to/qa-config.json

# Delete a project (prompts for confirmation)
python -m src.cli project delete myapp
```

Each project gets its own isolated storage:

```
~/.qa-framework/
  active-project          ← which project is currently active
  projects/
    kreitech/
      config.json         ← target URL, auth, hints, AI settings
      runs/               ← run output (test results, evidence)
      qa-reports/         ← HTML and JSON reports
    myapp/
      config.json
      runs/
      qa-reports/
```

> **Backward compatible:** `--config path/to/file.json` always works as before and bypasses project resolution.

---

## Configuration

### Minimal

```json
{
  "target_url": "https://yoursite.com"
}
```

### With Authentication

Passwords are never stored in plain text — use `env:VAR_NAME` to resolve from environment variables at runtime.

```json
{
  "target_url": "https://yoursite.com",
  "auth": {
    "login_url": "https://yoursite.com/login",
    "username": "testuser@example.com",
    "password": "env:QA_TEST_PASSWORD"
  }
}
```

```bash
export QA_TEST_PASSWORD=secret
python -m src.cli run
```

### With Hints

Natural language hints guide AI test priorities without writing specs.

```json
{
  "target_url": "https://yoursite.com",
  "hints": [
    "The checkout flow is our most critical path",
    "Search has been buggy with special characters",
    "We just redesigned the pricing page"
  ]
}
```

### Key Settings

| Field | Default | Description |
|---|---|---|
| `target_url` | — | Site to test (required) |
| `ai_provider` | `"anthropic"` | `"anthropic"` or `"ollama"` |
| `ai_model` | `"claude-opus-4-6"` | Claude model or Ollama model name |
| `categories` | `["functional","visual","security"]` | Test types to generate |
| `max_tests_per_run` | `20` | Cap on AI-generated tests |
| `max_execution_time_seconds` | `1800` | Pipeline timeout (30 min) |
| `staleness_threshold_days` | `7` | Days before coverage is considered stale |

→ **[Complete configuration reference](./REQUIREMENTS.md#configuration)**

---

## CLI Reference

### Project Management

```bash
python -m src.cli project create --name <n> --target <url>   # Create a project
python -m src.cli project import --name <n> [--config <f>]   # Import existing config
python -m src.cli project list                                # List all projects
python -m src.cli project use <name>                         # Set active project
python -m src.cli project history <name> [--last N]          # View run history
python -m src.cli project delete <name>                      # Delete a project
```

### Pipeline

```bash
python -m src.cli run [--project <n>]                        # Full pipeline
python -m src.cli crawl [--project <n>]                      # Crawl only
python -m src.cli plan [--project <n>]                       # Plan only
python -m src.cli execute --plan-file <f> [--project <n>]    # Execute only
```

All pipeline commands resolve the config in this order:
1. `--config path` (always wins, legacy mode)
2. `--project name`
3. Active project (`~/.qa-framework/active-project`)
4. `qa-config.json` in current directory

### Coverage

```bash
python -m src.cli coverage [--project <n>]          # View coverage summary
python -m src.cli coverage --gaps [--project <n>]   # Show untested areas
python -m src.cli coverage --reset [--project <n>]  # Reset history
```

### Hints

```bash
python -m src.cli hint add "Checkout flow is critical" [--config <f>]
python -m src.cli hint list [--config <f>]
python -m src.cli hint clear [--config <f>]
```

### Initialization (legacy)

```bash
python -m src.cli init --target https://yoursite.com   # Create qa-config.json
```

---

## How It Works

**Four-stage pipeline:**

1. **Crawl** — Real browser discovers pages, forms, elements, and APIs
2. **Plan** — Claude AI analyzes structure and generates contextual tests
3. **Execute** — Playwright runs tests with AI-assisted error recovery
4. **Report** — HTML/JSON reports with screenshots and AI insights

→ **[Detailed pipeline walkthrough](./OVERVIEW.md#how-it-works)**

---

## What Gets Generated

After `python -m src.cli run` with a named project:

```
~/.qa-framework/projects/mysite/
  runs/
    {run-id}/
      run_result.json      ← pass/fail stats, timing
      evidence/            ← screenshots per test step
  qa-reports/
    report_{run-id}.html   ← interactive HTML report
    report_{run-id}.json   ← machine-readable results

.qa-framework/             ← local working data (in project dir)
  site_model/model.json    ← crawled site structure
  coverage/registry.json   ← coverage history
```

**The HTML report includes:**
- Pass/fail statistics with visual breakdown
- AI-generated natural language summary
- Step-by-step execution with screenshots
- Regression detection (tests that newly fail vs. last run)
- Coverage metrics

---

## Requirements

- **Python 3.12+**
- **Chromium** (via `playwright install chromium`)
- **Anthropic API key** — recommended; the framework still runs without it in basic mode

### Environment Variables

| Variable | Required | Purpose |
|---|---|---|
| `ANTHROPIC_API_KEY` | Recommended | Claude AI for test generation and recovery |
| `OLLAMA_BASE_URL` | No | Custom Ollama endpoint (default: `http://localhost:11434`) |
| Any `env:VAR_NAME` in config | Depends | Credentials injected at runtime |

---

## Real-World Example

```bash
# Set up a new project
python -m src.cli project create --name myshop --target https://myshop.com
python -m src.cli hint add "Checkout flow is business-critical" --config ~/.qa-framework/projects/myshop/config.json
python -m src.cli hint add "Product search has been unreliable"  --config ~/.qa-framework/projects/myshop/config.json

# Run
export ANTHROPIC_API_KEY=your_key
python -m src.cli run

# Check history next week
python -m src.cli project history myshop
```

**Typical findings:**
- "Add to cart" button selector changed → AI auto-fixed
- XSS vulnerability in product review form → Flagged
- Visual regression: Logo alignment shifted → Screenshot diff
- Checkout flow: 100% passing

---

## Documentation

| Doc | Contents |
|---|---|
| [README.md](./README.md) | Quick start (you are here) |
| [OVERVIEW.md](./OVERVIEW.md) | Full introduction: pipeline, features, comparisons |
| [REQUIREMENTS.md](./REQUIREMENTS.md) | Complete technical specification |
| [CONTRIBUTING.md](./CONTRIBUTING.md) | Development setup and contribution guide |
| [SECURITY.md](./SECURITY.md) | Reporting vulnerabilities |

---

## Contributing

We welcome contributions. See [CONTRIBUTING.md](./CONTRIBUTING.md) to get started.

Areas of interest:
- Accessibility testing category
- Multi-browser support (Firefox, WebKit)
- Enhanced authentication (OAuth, SAML)
- Scheduled / CI-triggered runs

Please report security vulnerabilities via [SECURITY.md](./SECURITY.md).

---

## License

Apache License 2.0 — see [LICENSE](./LICENSE).
