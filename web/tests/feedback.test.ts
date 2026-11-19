import { describe, expect, it } from 'vitest'
import { sendFeedback } from '../src/state/feedback'

const fake = (status: number | Error) => {
  const calls: { url: string; init: RequestInit }[] = []
  const post = (async (url: string, init: RequestInit) => {
    calls.push({ url, init })
    if (status instanceof Error) throw status
    return new Response(null, { status })
  }) as unknown as typeof fetch
  return { calls, post }
}

describe('room feedback', () => {
  it('sends only the place, kind and a trimmed note', async () => {
    const f = fake(204)
    expect(await sendFeedback('baskin-engineering-152', 'tip', '  behind the vending machines  ', '/fb', f.post)).toBe('ok')
    expect(JSON.parse(f.calls[0].init.body as string)).toEqual({ place: 'baskin-engineering-152', kind: 'tip', message: 'behind the vending machines' })
    expect(f.calls[0].init.credentials).toBe('omit')
    await sendFeedback('baskin-engineering-152', 'easy', '   ', '/fb', f.post)
    expect(JSON.parse(f.calls[1].init.body as string)).toEqual({ place: 'baskin-engineering-152', kind: 'easy' })
  })
  it('caps the note at 280 characters', async () => {
    const f = fake(204)
    await sendFeedback('p', 'tip', 'x'.repeat(400), '/fb', f.post)
    expect(JSON.parse(f.calls[0].init.body as string).message).toHaveLength(280)
  })
  it('maps server answers', async () => {
    expect(await sendFeedback('p', 'easy', '', '/fb', fake(429).post)).toBe('busy')
    expect(await sendFeedback('p', 'easy', '', '/fb', fake(400).post)).toBe('rejected')
    expect(await sendFeedback('p', 'easy', '', '/fb', fake(503).post)).toBe('failed')
    expect(await sendFeedback('p', 'easy', '', '/fb', fake(new TypeError('offline')).post)).toBe('failed')
    expect(await sendFeedback('p', 'easy', '', undefined, fake(204).post)).toBe('failed')
  })
})
