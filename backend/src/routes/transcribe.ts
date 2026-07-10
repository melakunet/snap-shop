import { Hono } from 'hono'
import type { Env, Variables } from '../lib/schema'
import { errorBody } from '../lib/errors'
import { transcribeWithWhisper } from '../services/whisper'

const route = new Hono<{ Bindings: Env; Variables: Variables }>()

const MAX_AUDIO_BYTES = 25 * 1024 * 1024 // 25 MB — Groq Whisper upload limit

// POST /transcribe — accepts multipart audio field, returns { transcript: string }.
// When GROQ_API_KEY is absent returns the mock transcript so CI stays green.
route.post('/', async (c) => {
  let formData: FormData
  try {
    formData = await c.req.formData()
  } catch {
    return c.json(errorBody('invalid_input', 'Expected multipart/form-data'), 400)
  }

  const audio = formData.get('audio')
  if (!(audio instanceof File)) {
    return c.json(errorBody('invalid_input', 'Missing audio field'), 400)
  }

  if (audio.size > MAX_AUDIO_BYTES) {
    return c.json(
      errorBody('invalid_input', 'Audio file must be smaller than 25 MB'),
      400,
    )
  }

  const data = await audio.arrayBuffer()
  const transcript = await transcribeWithWhisper(data, audio.name || 'audio.m4a', c.env)

  return c.json({ transcript })
})

export default route
