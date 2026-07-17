export type ErrorCode =
  | 'unauthorized'
  | 'rate_limited'
  | 'invalid_input'
  | 'upstream_error'
  | 'no_products_found'
  | 'internal'

export function errorBody(code: ErrorCode, message: string) {
  return { error: { code, message } }
}
