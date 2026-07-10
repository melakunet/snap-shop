#!/usr/bin/env node
/**
 * Snap&Shop — backend latency check
 *
 * Phase-1 exit gate: P50(identify→shop end-to-end) < 6 000 ms
 *
 * Usage:
 *   SMOKE_URL=http://localhost:8787 npm run latency
 *   SMOKE_URL=http://localhost:8787 npm run latency -- --n-identify=20 --n-shop=10
 *   npm run latency -- --url=http://localhost:8787 --n-identify=5 --n-deep=5 --n-shop=3
 *
 * Flags:
 *   --url=<url>         Target base URL (overrides SMOKE_URL; one of the two is required)
 *   --n-identify=<n>    Runs for /identify/precision    [default: 10]
 *   --n-deep=<n>        Runs for /identify/deep         [default: 10]
 *   --n-shop=<n>        Runs for /shop in isolation     [default:  5, cache-busted]
 *
 * Prerequisites:
 *   - Target backend must be running with DEV_AUTH_BYPASS=1 (see .dev.vars.example).
 *   - This script sends NO auth header. Backend API keys (ANTHROPIC_API_KEY, SERPAPI_KEY, …)
 *     must be set on the server — never in this script.
 *   - Node.js 18+ required (native fetch, FormData, Blob).
 *
 * Exit codes: 0 = gate PASS, 1 = gate FAIL or run errors.
 */

import { readFileSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import { dirname, join }  from 'node:path'
import process            from 'node:process'

// ── Constants ────────────────────────────────────────────────────────────────

const P50_GATE_MS  = 6_000   // Phase-1 exit gate
const DEEP_FRAMES  = 8       // frames per deep-scan request
const SHOP_QUERY   = 'Sony WH-1000XM5 wireless headphones'
const SEP          = '─'.repeat(80)

// ── Helpers ───────────────────────────────────────────────────────────────────

function die(msg: string): never {
  console.error(`\nERROR: ${msg}\n`)
  process.exit(1)
}

// ── CLI parsing ───────────────────────────────────────────────────────────────

function parseArgs() {
  if (typeof fetch !== 'function') die('Node.js 18 or later is required (native fetch).')

  const argv = process.argv.slice(2)

  const flagStr = (name: string) => {
    const m = argv.find(a => a.startsWith(`--${name}=`))
    return m ? m.slice(`--${name}=`.length) : undefined
  }

  const flagInt = (name: string, def: number): number => {
    const v = flagStr(name)
    if (!v) return def
    const n = parseInt(v, 10)
    if (Number.isNaN(n) || n < 1) die(`--${name} must be a positive integer (got: "${v}")`)
    return n
  }

  const url = (flagStr('url') ?? process.env['SMOKE_URL'] ?? '').replace(/\/$/, '')
  if (!url) {
    console.error(`
ERROR: Target URL is required.

  Via env var (recommended):
    SMOKE_URL=http://localhost:8787 npm run latency

  Via flag:
    npm run latency -- --url=http://localhost:8787

Backend API keys (ANTHROPIC_API_KEY, SERPAPI_KEY, …) must be configured on the server,
not in this script. The target must have DEV_AUTH_BYPASS=1 set in wrangler.toml or .dev.vars.
`)
    process.exit(1)
  }

  return {
    url,
    nIdentify : flagInt('n-identify', 10),
    nDeep     : flagInt('n-deep', 10),
    nShop     : flagInt('n-shop', 5),
  }
}

// ── Fixture images ────────────────────────────────────────────────────────────

// Resolved relative to scripts/ → backend/test/smoke/sample.jpg
const sampleBuf = readFileSync(
  join(dirname(fileURLToPath(import.meta.url)), '..', 'test', 'smoke', 'sample.jpg'),
)

/** Precision form: single `image` field */
function precisionForm(): FormData {
  const f = new FormData()
  f.append('image', new Blob([sampleBuf], { type: 'image/jpeg' }), 'sample.jpg')
  return f
}

/** Deep-scan form: DEEP_FRAMES copies of the sample under the `frames[]` field */
function deepForm(): FormData {
  const f = new FormData()
  for (let i = 0; i < DEEP_FRAMES; i++) {
    f.append('frames[]', new Blob([sampleBuf], { type: 'image/jpeg' }), `frame_${i}.jpg`)
  }
  return f
}

// ── HTTP helpers ──────────────────────────────────────────────────────────────

async function guardStatus(res: Response, label: string, run: number): Promise<void> {
  if (res.status === 401) {
    const body = await res.text()
    console.error(`
  ⚠  401 Unauthorized on ${label}
     This script sends no auth header. DEV_AUTH_BYPASS must be active on the target.

     In backend/wrangler.toml:    DEV_AUTH_BYPASS = "1"
     Or in backend/.dev.vars:     DEV_AUTH_BYPASS=1

     Server response: ${body.slice(0, 300)}
`)
    process.exit(1)
  }
  if (!res.ok) {
    const body = await res.text()
    throw new Error(`[run ${run}] ${label} → HTTP ${res.status}: ${body.slice(0, 200)}`)
  }
}

// ── Per-endpoint run functions ────────────────────────────────────────────────

interface PrecisionRun {
  precisionMs : number
  shopMs      : number
  e2eMs       : number
  query       : string
}

/** POST sample image to /identify/precision, then chain /shop with the returned query. */
async function runPrecision(base: string, run: number): Promise<PrecisionRun> {
  const t0  = Date.now()
  const res = await fetch(`${base}/identify/precision`, { method: 'POST', body: precisionForm() })
  await guardStatus(res, '/identify/precision', run)
  const precisionMs = Date.now() - t0

  const data  = (await res.json()) as Record<string, unknown>
  const query = (data['search_query'] as string | undefined) ?? ''
  if (!query) throw new Error(`[run ${run}] /identify/precision returned no search_query`)

  // Chain /shop — real pipeline measurement (query from identify; not cache-busted here)
  const t1       = Date.now()
  const shopRes  = await fetch(`${base}/shop`, {
    method  : 'POST',
    headers : { 'Content-Type': 'application/json' },
    body    : JSON.stringify({ query, retailer_whitelist: [] }),
  })
  await guardStatus(shopRes, '/shop (e2e chain)', run)
  const shopMs = Date.now() - t1

  return { precisionMs, shopMs, e2eMs: precisionMs + shopMs, query }
}

/** POST DEEP_FRAMES copies of the sample to /identify/deep, return total latency. */
async function runDeep(base: string, run: number): Promise<number> {
  const t0  = Date.now()
  const res = await fetch(`${base}/identify/deep`, { method: 'POST', body: deepForm() })
  await guardStatus(res, '/identify/deep', run)
  return Date.now() - t0
}

/**
 * POST to /shop with a cache-busted query (unique per session+run).
 * Consumes SerpAPI quota on every call — keep --n-shop low (default 5).
 */
async function runShopIsolated(base: string, run: number, salt: string): Promise<number> {
  const query = `${SHOP_QUERY} _${salt}r${run}`   // unique suffix busts Redis cache
  const t0    = Date.now()
  const res   = await fetch(`${base}/shop`, {
    method  : 'POST',
    headers : { 'Content-Type': 'application/json' },
    body    : JSON.stringify({ query, retailer_whitelist: [] }),
  })
  await guardStatus(res, '/shop (isolated)', run)
  return Date.now() - t0
}

// ── Statistics ────────────────────────────────────────────────────────────────

function percentile(sorted: number[], p: number): number {
  if (!sorted.length) return 0
  return sorted[Math.max(0, Math.ceil((p / 100) * sorted.length) - 1)]!
}

interface Stats { p50: number; p95: number; min: number; max: number }

function computeStats(ms: number[]): Stats {
  const s = [...ms].sort((a, b) => a - b)
  return { p50: percentile(s, 50), p95: percentile(s, 95), min: s[0]!, max: s[s.length - 1]! }
}

const LABEL_W = 38

function printRow(label: string, ms: number[], total: number, gateMs?: number): number {
  const pad = (n: number, w = 6) => String(n).padStart(w)
  if (!ms.length) {
    console.log(`  ${'(no data)'.padEnd(LABEL_W)}  n=0/${total}`)
    return Infinity
  }
  const { p50, p95, min, max } = computeStats(ms)
  const failNote = ms.length < total ? `  (${total - ms.length} failed)` : ''
  const gateNote = gateMs != null ? (p50 < gateMs ? '  ✓ PASS' : '  ✗ FAIL') : ''
  console.log(
    `  ${label.padEnd(LABEL_W)}  P50:${pad(p50)} ms  P95:${pad(p95)} ms  min:${pad(min)} ms  max:${pad(max)} ms  n=${ms.length}/${total}${failNote}${gateNote}`,
  )
  return p50
}

// ── Preflight ─────────────────────────────────────────────────────────────────

async function preflight(url: string): Promise<void> {
  process.stdout.write(`  Connecting to ${url}/health … `)
  let res: Response
  try {
    res = await fetch(`${url}/health`)
  } catch (err) {
    process.stdout.write('FAIL\n')
    const msg = err instanceof Error ? err.message : String(err)
    die(`Cannot reach ${url} — ${msg}\n  Is wrangler dev running? Start it with: cd backend && npm run dev`)
  }
  if (!res.ok) {
    process.stdout.write('FAIL\n')
    const body = await res.text()
    die(`/health returned HTTP ${res.status}: ${body.slice(0, 200)}`)
  }
  process.stdout.write('OK\n\n')
}

// ── Main ──────────────────────────────────────────────────────────────────────

async function main(): Promise<void> {
  const { url, nIdentify, nDeep, nShop } = parseArgs()
  const salt = Date.now().toString(36)

  console.log(`\nSnap&Shop — Latency Check`)
  console.log(`Target    : ${url}`)
  console.log(`Suites    : precision=${nIdentify}  deep=${nDeep}  shop(isolated)=${nShop}`)
  console.log(`Gate      : P50(identify→shop e2e) < ${P50_GATE_MS} ms`)
  console.log(`Auth      : none (assumes DEV_AUTH_BYPASS=1 on target)\n`)

  await preflight(url)

  // ── Suite 1: /identify/precision + chained /shop (e2e) ─────────────────
  console.log(`${SEP}\n Suite 1 — /identify/precision  +  /shop (chained e2e)  [${nIdentify} runs]\n${SEP}`)

  const identMs: number[] = []
  const e2eMs  : number[] = []

  for (let i = 1; i <= nIdentify; i++) {
    try {
      const r = await runPrecision(url, i)
      identMs.push(r.precisionMs)
      e2eMs.push(r.e2eMs)
      console.log(
        `  run ${String(i).padStart(2)}  identify: ${String(r.precisionMs).padStart(5)} ms` +
        `  shop: ${String(r.shopMs).padStart(5)} ms` +
        `  e2e: ${String(r.e2eMs).padStart(5)} ms` +
        `  "${r.query.slice(0, 50)}"`,
      )
    } catch (err) {
      console.error(`  run ${String(i).padStart(2)}  ERROR: ${(err as Error).message}`)
    }
  }

  // ── Suite 2: /identify/deep ─────────────────────────────────────────────
  console.log(`\n${SEP}\n Suite 2 — /identify/deep  [${nDeep} runs, ${DEEP_FRAMES} frames each]\n${SEP}`)

  const deepMs: number[] = []

  for (let i = 1; i <= nDeep; i++) {
    try {
      const ms = await runDeep(url, i)
      deepMs.push(ms)
      console.log(`  run ${String(i).padStart(2)}  ${String(ms).padStart(6)} ms`)
    } catch (err) {
      console.error(`  run ${String(i).padStart(2)}  ERROR: ${(err as Error).message}`)
    }
  }

  // ── Suite 3: /shop isolated (cache-busted) ──────────────────────────────
  console.log(`\n${SEP}\n Suite 3 — /shop isolated  [${nShop} runs, cache-busted — consumes SerpAPI quota]\n${SEP}`)

  const shopMs: number[] = []

  for (let i = 1; i <= nShop; i++) {
    try {
      const ms = await runShopIsolated(url, i, salt)
      shopMs.push(ms)
      console.log(`  run ${String(i).padStart(2)}  ${String(ms).padStart(6)} ms`)
    } catch (err) {
      console.error(`  run ${String(i).padStart(2)}  ERROR: ${(err as Error).message}`)
    }
  }

  // ── Summary table ────────────────────────────────────────────────────────
  console.log(`\n${SEP}\n Results\n${SEP}`)
  printRow('/identify/precision',           identMs, nIdentify)
  printRow('/identify/deep (8 frames)',     deepMs,  nDeep)
  printRow('/shop isolated (cache-busted)', shopMs,  nShop)
  console.log()
  const e2eP50 = printRow('identify→shop e2e  ←GATE', e2eMs, nIdentify, P50_GATE_MS)
  console.log(SEP)

  const gatePass = Number.isFinite(e2eP50) && e2eP50 < P50_GATE_MS
  const allRan   = e2eMs.length === nIdentify

  if (!Number.isFinite(e2eP50) || e2eMs.length === 0) {
    console.error(`FAIL — no successful e2e runs; cannot evaluate gate\n`)
    process.exit(1)
  } else if (gatePass && allRan) {
    console.log(`\nPASS — P50 ${e2eP50} ms < ${P50_GATE_MS} ms  (${nIdentify}/${nIdentify} e2e runs)\n`)
    process.exit(0)
  } else if (gatePass) {
    console.log(`\nPASS (gate) — P50 ${e2eP50} ms < ${P50_GATE_MS} ms  but ${nIdentify - e2eMs.length} run(s) errored\n`)
    process.exit(1)   // partial data — flag as fail for CI
  } else {
    console.error(`\nFAIL — P50 ${e2eP50} ms >= gate of ${P50_GATE_MS} ms  (${e2eMs.length}/${nIdentify} e2e runs)\n`)
    process.exit(1)
  }
}

main().catch((err: unknown) => {
  console.error('Fatal:', err)
  process.exit(1)
})
