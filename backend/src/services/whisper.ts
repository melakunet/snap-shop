import type { Env } from '../lib/schema'

const WHISPER_URL = 'https://api.groq.com/openai/v1/audio/transcriptions'

// Returned when GROQ_API_KEY is absent so dev/CI works without a real key.
export const MOCK_TRANSCRIPT = 'mock transcript'

/**
 * Send an audio file to Groq whisper-large-v3 and return the transcript.
 * Returns MOCK_TRANSCRIPT when no API key is configured.
 * Returns '' on API failure (transcript is a best-effort hint, not required).
 */
export async function transcribeWithWhisper(
  audioData: ArrayBuffer,
  filename: string,
  env: Env,
): Promise<string> {
  if (!env.GROQ_API_KEY) return MOCK_TRANSCRIPT

  const form = new FormData()
  form.append('file', new Blob([audioData]), filename)
  form.append('model', 'whisper-large-v3')
  form.append('response_format', 'json')

  try {
    const res = await fetch(WHISPER_URL, {
      method: 'POST',
      headers: { Authorization: `Bearer ${env.GROQ_API_KEY}` },
      body: form,
    })
    if (!res.ok) return ''
    const data = (await res.json()) as { text?: string }
    return typeof data.text === 'string' ? data.text.trim() : ''
  } catch {
    return ''
  }
}
