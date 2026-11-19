export const FEEDBACK_URL = import.meta.env.VITE_FEEDBACK_URL as string | undefined
export const MAX_MESSAGE = 280

export type FeedbackKind = 'easy' | 'unclear' | 'tip' | 'missing'
export type FeedbackResult = 'ok' | 'rejected' | 'busy' | 'failed'

/** Sends anonymous room feedback: the place, the kind and an optional note, nothing about the sender. */
export async function sendFeedback(place: string, kind: FeedbackKind, message = '', url = FEEDBACK_URL, post: typeof fetch = fetch): Promise<FeedbackResult> {
  if (!url) return 'failed'
  const text = message.trim().slice(0, MAX_MESSAGE)
  try {
    const r = await post(url, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(text ? { place, kind, message: text } : { place, kind }),
      credentials: 'omit',
      keepalive: true,
    })
    if (r.status === 204) return 'ok'
    if (r.status === 429) return 'busy'
    if (r.status >= 400 && r.status < 500) return 'rejected'
    return 'failed'
  } catch {
    return 'failed'
  }
}

/** Remembers which rooms this browser already marked easy, so one tap is one vote. */
export function markedEasy(place: string): boolean {
  try {
    return (JSON.parse(localStorage.getItem('feedback_easy') ?? '[]') as string[]).includes(place)
  } catch {
    return false
  }
}
export function rememberEasy(place: string) {
  try {
    const list = JSON.parse(localStorage.getItem('feedback_easy') ?? '[]') as string[]
    localStorage.setItem('feedback_easy', JSON.stringify([place, ...list.filter((p) => p !== place)].slice(0, 200)))
  } catch {
    /* storage may be unavailable */
  }
}
