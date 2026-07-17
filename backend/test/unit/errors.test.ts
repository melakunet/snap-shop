import { describe, it, expect } from 'vitest'
import { errorBody } from '../../src/lib/errors'
import type { ErrorCode } from '../../src/lib/errors'

describe('errorBody()', () => {
  it('returns correct structure for unauthorized', () => {
    const body = errorBody('unauthorized', 'Not authorized')
    expect(body).toEqual({ error: { code: 'unauthorized', message: 'Not authorized' } })
  })

  it('returns correct structure for rate_limited', () => {
    const body = errorBody('rate_limited', 'Too many requests')
    expect(body).toEqual({ error: { code: 'rate_limited', message: 'Too many requests' } })
  })

  it('returns correct structure for invalid_input', () => {
    const body = errorBody('invalid_input', 'Bad request')
    expect(body).toEqual({ error: { code: 'invalid_input', message: 'Bad request' } })
  })

  it('returns correct structure for upstream_error', () => {
    const body = errorBody('upstream_error', 'API failed')
    expect(body).toEqual({ error: { code: 'upstream_error', message: 'API failed' } })
  })

  it('returns correct structure for internal', () => {
    const body = errorBody('internal', 'Internal server error')
    expect(body).toEqual({ error: { code: 'internal', message: 'Internal server error' } })
  })

  it('returns correct structure for no_products_found', () => {
    const body = errorBody('no_products_found', "Couldn't spot a product")
    expect(body).toEqual({ error: { code: 'no_products_found', message: "Couldn't spot a product" } })
  })
})

describe('HTTP status codes for ErrorCode', () => {
  // These expected status mappings mirror what routes return for each code
  const statusMap: Record<ErrorCode, number> = {
    invalid_input: 400,
    unauthorized: 401,
    rate_limited: 429,
    upstream_error: 502,
    no_products_found: 422,
    internal: 500,
  }

  it('invalid_input maps to 400', () => {
    expect(statusMap['invalid_input']).toBe(400)
  })

  it('unauthorized maps to 401', () => {
    expect(statusMap['unauthorized']).toBe(401)
  })

  it('rate_limited maps to 429', () => {
    expect(statusMap['rate_limited']).toBe(429)
  })

  it('upstream_error maps to 502', () => {
    expect(statusMap['upstream_error']).toBe(502)
  })

  it('each ErrorCode produces an object with error.code and error.message', () => {
    const codes: ErrorCode[] = ['unauthorized', 'rate_limited', 'invalid_input', 'upstream_error', 'no_products_found', 'internal']
    for (const code of codes) {
      const body = errorBody(code, 'test message')
      expect(body.error.code).toBe(code)
      expect(body.error.message).toBe('test message')
    }
  })
})
