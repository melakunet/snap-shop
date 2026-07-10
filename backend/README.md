# Snap & Shop — Backend API

Cloudflare Workers + Hono + TypeScript REST API for product identification and price comparison.

## Environment Variables

### Required

| Variable | Description |
|---|---|
| `ENVIRONMENT` | Runtime environment (`dev` or `production`) — set via `wrangler.toml` vars |
| `APPLE_BUNDLE_ID` | iOS app bundle ID for Apple JWT validation |
| `ANTHROPIC_API_KEY` | Anthropic API key for Claude Vision |
| `GEMINI_API_KEY` | Google Gemini API key for multi-frame identification |
| `SERPAPI_KEY` | SerpAPI key for Google Shopping results |
| `SENTRY_DSN` | Sentry DSN for error tracking |
| `PLAUSIBLE_DOMAIN` | Plausible analytics domain |

### Optional

| Variable | Description |
|---|---|
| `UPSTASH_REDIS_REST_URL` | Upstash Redis REST URL for shared cache (falls back to in-memory) |
| `UPSTASH_REDIS_REST_TOKEN` | Upstash Redis REST token |
| `DEV_AUTH_BYPASS` | Set to `1` to skip Apple JWT validation in development |
| `UPCITEMDB_KEY` | UPCitemdb API key for barcode lookup fallback |
| `GROQ_API_KEY` | Groq API key for Llama 4 Scout free-tier vision (first-pass before Claude) |
| `BESTBUY_API_KEY` | Best Buy API key for price results |
| `EBAY_APP_ID` | eBay Browse API app ID (OAuth App token) for price results |

Set secrets with:
```
wrangler secret put <NAME> [--env production]
```

For local development, copy the template from `.dev.vars` and fill in values. This file is gitignored.

## Scripts

| Command | Description |
|---|---|
| `npm run dev` | Start local dev server on port 8787 via `wrangler dev` |
| `npm test` | Run vitest unit test suite |
| `npm run type-check` | TypeScript type-check without emitting |
| `npm run deploy` | Deploy to Cloudflare Workers production environment |
| `npm run deploy:dev` | Deploy to default (dev) Workers environment |
| `npm run latency` | Run latency benchmark and Phase-1 exit gate (see below) |

## Latency Check / Exit Gate

**Gate:** P50(identify→shop end-to-end) < 6 000 ms

The `latency` script runs three benchmark suites against a live backend and checks the Phase-1 exit gate. The backend must be running with `DEV_AUTH_BYPASS=1` — the script sends no auth header.

```bash
# Start the dev backend first (in a separate terminal):
cd backend && npm run dev

# Then run the latency check:
SMOKE_URL=http://localhost:8787 npm run latency
```

Flags (all optional):

| Flag | Default | Description |
|---|---|---|
| `--url=<url>` | `$SMOKE_URL` | Target base URL (required if env var not set) |
| `--n-identify=<n>` | 10 | Runs for `/identify/precision` + chained `/shop` (e2e gate) |
| `--n-deep=<n>` | 10 | Runs for `/identify/deep` (8 frames each) |
| `--n-shop=<n>` | 5 | Runs for `/shop` isolated (cache-busted — consumes SerpAPI quota) |

Example with custom counts:

```bash
SMOKE_URL=http://localhost:8787 npm run latency -- --n-identify=20 --n-shop=3
```

Exit code `0` = gate PASS; `1` = gate FAIL or run errors.

## API Endpoints

| Route | Auth | Description |
|---|---|---|
| `GET /health` | None | Liveness probe — returns `{ ok: true, env }` |
| `GET /docs` | None | Swagger UI |
| `GET /swagger.json` | None | OpenAPI spec |
| `POST /identify/precision` | Apple JWT | Claude Vision single-image product ID |
| `POST /identify/deep` | Apple JWT | Gemini multi-frame product ID |
| `POST /shop` | Apple JWT | Price comparison across Best Buy, eBay, SerpAPI + Redis cache |

### POST /identify/precision

Multipart form fields:
- `image` (required): JPEG, PNG, GIF, or WebP file, max 10 MB
- `barcode` (optional): UPC/EAN barcode string — triggers fast-path lookup before vision

Header: `X-Tier: pro` enables Opus escalation on low-confidence results.

Provider chain (in order):
1. Barcode lookup (Open Food Facts → UPCitemdb) if `barcode` field present
2. Groq Llama 4 Scout (if `GROQ_API_KEY` set and confidence ≥ 0.6)
3. Claude Sonnet 4.6 (→ Opus 4.7 for Pro tier + confidence < 0.6)

## Dev tooling (MCP)

Two MCP servers are recommended for local development and testing:

### GitHub MCP Server

Provides GitHub repository access (issues, PRs, code search) from within the Claude Code agent.

```json
{
  "mcpServers": {
    "github": {
      "command": "npx",
      "args": ["@github-mcp/server"],
      "env": {
        "GITHUB_PERSONAL_ACCESS_TOKEN": "<your_github_pat>"
      }
    }
  }
}
```

Create a GitHub PAT at https://github.com/settings/tokens with `repo` scope.

### Apify E-Commerce Intelligence MCP

Live price and catalog testing against real e-commerce data for validating `/shop` responses.

```json
{
  "mcpServers": {
    "apify": {
      "command": "npx",
      "args": ["apify-mcp-server"],
      "env": {
        "APIFY_TOKEN": "<your_apify_token>"
      }
    }
  }
}
```

Get an Apify token at https://console.apify.com/account/integrations.

Add the config above to your `~/.claude/claude_desktop_config.json` (Claude Desktop) or `.claude/settings.json` (Claude Code CLI).
