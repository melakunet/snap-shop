import { z } from 'zod'

export const Env = z.object({
  ENVIRONMENT: z.string(),
  APPLE_BUNDLE_ID: z.string(),
  ANTHROPIC_API_KEY: z.string(),
  GEMINI_API_KEY: z.string(),
  SERPAPI_KEY: z.string(),
  UPSTASH_REDIS_REST_URL: z.string(),
  UPSTASH_REDIS_REST_TOKEN: z.string(),
  SENTRY_DSN: z.string(),
  PLAUSIBLE_DOMAIN: z.string(),
  DEV_AUTH_BYPASS: z.string().optional(),
})

export type Env = z.infer<typeof Env>
