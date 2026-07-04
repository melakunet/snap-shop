#!/usr/bin/env node
/**
 * Phase 1 exit-gate smoke test
 * Usage: node test/smoke/smoke.mjs
 * Requires wrangler dev running on port 8787 with DEV_AUTH_BYPASS=1
 */

import { readFileSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import { dirname, join } from 'node:path'

const __dir = dirname(fileURLToPath(import.meta.url))
const BASE_URL = process.env.SMOKE_URL ?? 'http://localhost:8787'
const RUNS = 10
const P50_MAX_MS = 6000
const MIN_PRICES = 5
const AUTH_HEADER = 'Bearer smoke-test-token'
const USER_HEADER = 'smoke-user'

const samplePath = join(__dir, 'sample.jpg')
const sampleBytes = readFileSync(samplePath)

async function runOnce(run) {
  const t0 = Date.now()

  // Step 1 — identify/precision
  const form = new FormData()
  form.append('image', new Blob([sampleBytes], { type: 'image/jpeg' }), 'sample.jpg')

  const identifyRes = await fetch(`${BASE_URL}/identify/precision`, {
    method: 'POST',
    headers: {
      Authorization: AUTH_HEADER,
      'X-Debug-User': USER_HEADER,
      'X-Tier': 'free',
    },
    body: form,
  })

  if (!identifyRes.ok) {
    const body = await identifyRes.text()
    throw new Error(`[run ${run}] /identify/precision ${identifyRes.status}: ${body.slice(0, 200)}`)
  }

  const identifyData = await identifyRes.json()
  const query = identifyData.search_query
  if (!query) throw new Error(`[run ${run}] identify returned no search_query`)

  // Step 2 — shop
  const shopRes = await fetch(`${BASE_URL}/shop`, {
    method: 'POST',
    headers: {
      Authorization: AUTH_HEADER,
      'X-Debug-User': USER_HEADER,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({ query, retailer_whitelist: [] }),
  })

  if (!shopRes.ok) {
    const body = await shopRes.text()
    throw new Error(`[run ${run}] /shop ${shopRes.status}: ${body.slice(0, 200)}`)
  }

  const shopData = await shopRes.json()
  const latencyMs = Date.now() - t0

  return { run, latencyMs, priceCount: shopData.length, query, shopData }
}

function percentile(sorted, p) {
  const idx = Math.ceil((p / 100) * sorted.length) - 1
  return sorted[Math.max(0, idx)]
}

async function main() {
  console.log(`\nSnap & Shop — Phase 1 smoke test`)
  console.log(`Target: ${BASE_URL}  |  Runs: ${RUNS}\n`)

  const latencies = []
  let allPass = true

  for (let i = 1; i <= RUNS; i++) {
    let result
    try {
      result = await runOnce(i)
    } catch (err) {
      console.error(`  run ${String(i).padStart(2)} — ERROR: ${err.message}`)
      allPass = false
      continue
    }

    const { latencyMs, priceCount, query } = result
    latencies.push(latencyMs)

    const runOk = priceCount >= MIN_PRICES
    if (!runOk) allPass = false

    const status = runOk ? 'PASS' : 'FAIL'
    console.log(
      `  run ${String(i).padStart(2)}  ${String(latencyMs).padStart(5)}ms  ${String(priceCount).padStart(2)} prices  [${status}]  "${query}"`,
    )
  }

  if (latencies.length === 0) {
    console.error('\nAll runs failed — cannot compute statistics.\n')
    process.exit(1)
  }

  const sorted = [...latencies].sort((a, b) => a - b)
  const p50 = percentile(sorted, 50)
  const p95 = percentile(sorted, 95)
  const min = sorted[0]
  const max = sorted[sorted.length - 1]

  console.log(`\n  Latency — min:${min}ms  P50:${p50}ms  P95:${p95}ms  max:${max}ms`)
  console.log(`  Runs with data: ${latencies.length}/${RUNS}`)

  const p50Pass = p50 < P50_MAX_MS
  const overallPass = allPass && p50Pass && latencies.length === RUNS

  if (!p50Pass) console.error(`  P50 ${p50}ms exceeds limit of ${P50_MAX_MS}ms — HARD FAIL`)
  if (!allPass) console.error(`  One or more runs returned fewer than ${MIN_PRICES} prices — HARD FAIL`)

  console.log(`\nP50: ${p50}ms  P95: ${p95}ms`)
  console.log(`\n${overallPass ? 'PASS' : 'FAIL'} — median ${p50}ms < ${P50_MAX_MS}ms, ${latencies.length === RUNS ? `all ${RUNS} runs ≥${MIN_PRICES} prices` : 'some runs failed'}\n`)
  process.exit(overallPass ? 0 : 1)
}

main().catch((err) => {
  console.error('Fatal:', err)
  process.exit(1)
})
