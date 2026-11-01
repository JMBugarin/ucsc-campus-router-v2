import { useEffect, type RefObject } from 'react'

/**
 * Adaptive glass strength, ported from TileLens (appearance.py): fill strength follows the
 * brightness and busyness of the map behind a panel. Sampled when the map goes idle, never per
 * frame, and only applied when it moved by more than a dead band so panels do not flicker.
 */
const MIN = 0.9
const MAX = 1.5
const GRID = 24
const DEAD_BAND = 0.07

type Listener = () => void
const listeners = new Set<Listener>()
let source: HTMLCanvasElement | null = null
let scratch: CanvasRenderingContext2D | null = null

export function setBackdropSource(canvas: HTMLCanvasElement | null) {
  source = canvas
  notifyBackdrop()
}
export function notifyBackdrop() {
  listeners.forEach((l) => l())
}

export function strengthFor(luma: number, busy: number, dark: boolean): number {
  const natural = dark ? 0.22 : 0.82
  const mismatch = Math.min(1, Math.abs(luma - natural) / 0.55)
  const texture = Math.min(1, busy / 0.2)
  const pressure = 0.65 * mismatch + 0.35 * texture
  return MIN + (MAX - MIN) * pressure
}

export function sampleBackdrop(el: Element): { luma: number; busy: number } | null {
  if (!source || !source.width) return null
  if (!scratch) {
    const c = document.createElement('canvas')
    c.width = c.height = GRID
    scratch = c.getContext('2d', { willReadFrequently: true })
  }
  if (!scratch) return null
  const r = el.getBoundingClientRect()
  const cr = source.getBoundingClientRect()
  const k = source.width / cr.width
  const x = Math.max(0, (r.left - cr.left) * k)
  const y = Math.max(0, (r.top - cr.top) * k)
  const w = Math.min(source.width - x, r.width * k)
  const h = Math.min(source.height - y, r.height * k)
  if (w < 4 || h < 4) return null
  try {
    scratch.drawImage(source, x, y, w, h, 0, 0, GRID, GRID)
    const d = scratch.getImageData(0, 0, GRID, GRID).data
    let sum = 0
    let sum2 = 0
    const n = GRID * GRID
    for (let i = 0; i < d.length; i += 4) {
      const l = (0.299 * d[i] + 0.587 * d[i + 1] + 0.114 * d[i + 2]) / 255
      sum += l
      sum2 += l * l
    }
    const mean = sum / n
    return { luma: mean, busy: Math.sqrt(Math.max(0, sum2 / n - mean * mean)) }
  } catch {
    return null
  }
}

export function useAdaptiveStrength(ref: RefObject<HTMLElement | null>, enabled = true) {
  useEffect(() => {
    const el = ref.current
    if (!el || !enabled) return
    let last = 1
    const update = () => {
      const s = sampleBackdrop(el)
      if (!s) return
      const dark = document.documentElement.dataset.resolvedTheme !== 'light'
      const next = strengthFor(s.luma, s.busy, dark)
      if (Math.abs(next - last) > DEAD_BAND) {
        last = next
        el.style.setProperty('--glass-strength', next.toFixed(2))
      }
    }
    listeners.add(update)
    update()
    return () => {
      listeners.delete(update)
    }
  }, [ref, enabled])
}
