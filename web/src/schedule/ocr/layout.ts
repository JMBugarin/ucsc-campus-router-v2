import { normalizeText } from './fields'
import { Box, type RecognizedText } from './recognized'

/** One word of recognized text with where it is and how sure the reader was of its line. */
export class Token {
  constructor(
    readonly text: string,
    readonly box: Box,
    readonly confidence: number,
  ) {}
  get left() {
    return this.box.left
  }
  get right() {
    return this.box.right
  }
  get top() {
    return this.box.top
  }
  get bottom() {
    return this.box.bottom
  }
  get centerY() {
    return this.box.centerY
  }
  get height() {
    return this.box.height
  }
  get width() {
    return this.box.width
  }
  toString() {
    return this.text
  }
}

export function median(values: number[]): number {
  const sorted = [...values].sort((a, b) => a - b)
  if (!sorted.length) return 0
  const mid = Math.floor(sorted.length / 2)
  return sorted.length % 2 ? sorted[mid] : (sorted[mid - 1] + sorted[mid]) / 2
}

const finite = (b: Box) => Number.isFinite(b.left) && Number.isFinite(b.top) && Number.isFinite(b.right) && Number.isFinite(b.bottom)

/** The reading's words. A line given without its words is spread over its box by length. */
export function tokensOf(reading: RecognizedText, limit = 6000): Token[] {
  const tokens: Token[] = []
  for (const line of reading.lines) {
    const text = normalizeText(line.text)
    if (!text || !finite(line.box)) continue
    const pieces = text.split(' ')
    const words = line.words.map((w) => [normalizeText(w.text), w.box] as const).filter(([t]) => t)
    if (words.length === pieces.length && words.map(([t]) => t).join(' ') === text) {
      for (const [word, box] of words) if (finite(box)) tokens.push(new Token(word, box, line.confidence))
    } else {
      let at = 0
      for (const piece of pieces) {
        const from = line.box.left + (line.box.width * at) / text.length
        const to = line.box.left + (line.box.width * (at + piece.length)) / text.length
        tokens.push(new Token(piece, new Box(from, line.box.top, to, line.box.bottom), line.confidence))
        at += piece.length + 1
      }
    }
    if (tokens.length > limit) break
  }
  return withoutRepeats(tokens)
}

/** A picture of the same page taken twice over (a scroll that overlaps itself) reads the same words twice. */
function withoutRepeats(tokens: Token[]): Token[] {
  const kept: Token[] = []
  const byText = new Map<string, Token[]>()
  for (const t of tokens) {
    const same = byText.get(t.text) ?? []
    byText.set(t.text, same)
    if (same.some((o) => overlap(o.box, t.box) > 0.6)) continue
    same.push(t)
    kept.push(t)
  }
  return kept
}

function overlap(a: Box, b: Box): number {
  const w = Math.min(a.right, b.right) - Math.max(a.left, b.left)
  const h = Math.min(a.bottom, b.bottom) - Math.max(a.top, b.top)
  if (w <= 0 || h <= 0) return 0
  const smaller = Math.min(a.width * a.height, b.width * b.height)
  return smaller <= 0 ? 0 : (w * h) / smaller
}

/** How tall ordinary text is in this picture, a little under the middle of the heights. */
export function typicalHeight(tokens: Token[]): number {
  const heights = tokens.filter((t) => /[A-Za-z0-9]{2}/.test(t.text)).map((t) => t.height)
  heights.sort((a, b) => a - b)
  return heights.length ? heights[Math.floor(heights.length * 0.35)] : 10
}

/** Marks the edge of a cell in a line's text; no field reader treats it as part of a value. */
export const CELL_BREAK = '‖'

/** Words that sit on one line of the picture, left to right. */
export class VisualLine {
  readonly tokens: Token[]
  readonly top: number
  readonly bottom: number
  readonly centerY: number
  readonly left: number
  readonly right: number
  readonly height: number
  constructor(tokens: Token[]) {
    this.tokens = [...tokens].sort((a, b) => a.left - b.left)
    this.top = Math.min(...this.tokens.map((t) => t.top))
    this.bottom = Math.max(...this.tokens.map((t) => t.bottom))
    this.centerY = this.tokens.reduce((s, t) => s + t.centerY, 0) / this.tokens.length
    this.left = this.tokens[0].left
    this.right = Math.max(...this.tokens.map((t) => t.right))
    this.height = median(this.tokens.map((t) => t.height))
  }
  get text() {
    return this.tokens.map((t) => t.text).join(' ')
  }
  /** The line's text with CELL_BREAK where the gap between words is wider than `gap`. */
  textWithBreaks(gap: number): string {
    let out = this.tokens[0].text
    for (let i = 1; i < this.tokens.length; i++) {
      out += this.tokens[i].left - this.tokens[i - 1].right > gap ? ` ${CELL_BREAK} ` : ' '
      out += this.tokens[i].text
    }
    return out
  }
}

/** Groups words into the lines they sit on, top to bottom. `h` is how tall ordinary text is. */
export function visualLines(tokens: Token[], h: number): VisualLine[] {
  const sorted = [...tokens].sort((a, b) => a.centerY - b.centerY)
  const groups: { tokens: Token[]; sum: number }[] = []
  for (const t of sorted) {
    let home: { tokens: Token[]; sum: number } | null = null
    for (let i = groups.length - 1; i >= 0 && i >= groups.length - 3; i--) {
      const g = groups[i]
      if (Math.abs(t.centerY - g.sum / g.tokens.length) <= 0.5 * Math.min(Math.max(t.height, h), 1.4 * h)) {
        home = g
        break
      }
    }
    if (!home) groups.push({ tokens: [t], sum: t.centerY })
    else {
      home.tokens.push(t)
      home.sum += t.centerY
    }
  }
  return groups.map((g) => new VisualLine(g.tokens)).sort((a, b) => a.centerY - b.centerY)
}
