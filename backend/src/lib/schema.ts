import { z } from 'zod'

export const Env = z.object({
  ENVIRONMENT: z.string(),
  APPLE_BUNDLE_ID: z.string(),
  ANTHROPIC_API_KEY: z.string(),
  GEMINI_API_KEY: z.string(),
  SERPAPI_KEY: z.string(),
  UPSTASH_REDIS_REST_URL: z.string().optional(),
  UPSTASH_REDIS_REST_TOKEN: z.string().optional(),
  SENTRY_DSN: z.string(),
  PLAUSIBLE_DOMAIN: z.string(),
  DEV_AUTH_BYPASS: z.string().optional(),
  // Part B — free-tier optional keys
  UPCITEMDB_KEY: z.string().optional(),
  GROQ_API_KEY: z.string().optional(),
  BESTBUY_API_KEY: z.string().optional(),
  EBAY_APP_ID: z.string().optional(),
})
export type Env = z.infer<typeof Env>

// Shared Hono context variables set by auth and telemetry middleware
export type Variables = { userId: string; requestId?: string; startMs?: number }

// Route A — single product identification result
export const IdentifyResult = z.object({
  brand: z.string(),
  model: z.string(),
  category: z.string(),
  distinguishing_features: z.array(z.string()),
  confidence: z.number().min(0).max(1),
  search_query: z.string(),
})
export type IdentifyResult = z.infer<typeof IdentifyResult>

// Route B — per-frame item (extends Route A schema)
export const DeepIdentifyItem = IdentifyResult.extend({
  frame_index: z.number().int().min(0),
})
export type DeepIdentifyItem = z.infer<typeof DeepIdentifyItem>

export const DeepIdentifyResult = z.array(DeepIdentifyItem)
export type DeepIdentifyResult = z.infer<typeof DeepIdentifyResult>

// /shop — request and response
export const ShopRequest = z.object({
  query: z.string().min(1, 'query must not be empty'),
  retailer_whitelist: z.array(z.string()),
})
export type ShopRequest = z.infer<typeof ShopRequest>

export const ShopItem = z.object({
  price: z.string(),
  extracted_price: z.number(),
  delivery: z.string(),
  source: z.string(),
  link: z.string(),
  thumbnail: z.string(),
})
export type ShopItem = z.infer<typeof ShopItem>
