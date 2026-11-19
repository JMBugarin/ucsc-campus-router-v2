/** A rectangle in picture pixels, measured from the top left. */
export class Box {
  constructor(
    readonly left: number,
    readonly top: number,
    readonly right: number,
    readonly bottom: number,
  ) {}
  get width() {
    return this.right - this.left
  }
  get height() {
    return this.bottom - this.top
  }
  get centerX() {
    return (this.left + this.right) / 2
  }
  get centerY() {
    return (this.top + this.bottom) / 2
  }
}

export interface RecognizedWord {
  text: string
  box: Box
}
/** One line of text found in a picture, where it is, and how sure the reader is of it (0 to 1). */
export interface RecognizedLine {
  text: string
  box: Box
  confidence: number
  words: RecognizedWord[]
}
export interface RecognizedText {
  width: number
  height: number
  lines: RecognizedLine[]
}

export class ReadingError extends Error {}

const num = (v: unknown): number => {
  if (typeof v !== 'number' || !Number.isFinite(v)) throw new ReadingError('A position or confidence is not a number.')
  return v
}
function box(item: Record<string, unknown>, width: number, height: number): Box {
  const x = num(item.x)
  const y = num(item.y)
  const w = num(item.w)
  const h = num(item.h)
  if (w < 0 || h < 0) throw new ReadingError('A box has a negative size.')
  return new Box(x * width, y * height, (x + w) * width, (y + h) * height)
}

/** From the saved shape the phone app records: positions are fractions of the picture's width and height. */
export function readingFromJson(json: unknown): RecognizedText {
  if (!json || typeof json !== 'object') throw new ReadingError('The reading is not a map.')
  const j = json as Record<string, unknown>
  const width = j.width
  const height = j.height
  if (!Number.isInteger(width) || !Number.isInteger(height) || (width as number) <= 0 || (height as number) <= 0) throw new ReadingError("The reading doesn't say how big the picture is.")
  if (!Array.isArray(j.lines)) throw new ReadingError('The reading has no lines.')
  const lines: RecognizedLine[] = []
  for (const item of j.lines as Record<string, unknown>[]) {
    if (!item || typeof item !== 'object') throw new ReadingError('A line is not a map.')
    if (typeof item.text !== 'string') throw new ReadingError('A line has no text.')
    const b = box(item, width as number, height as number)
    if (!item.text.trim()) continue
    const words = Array.isArray(item.words) ? (item.words as Record<string, unknown>[]) : []
    lines.push({
      text: item.text,
      box: b,
      confidence: Math.min(1, Math.max(0, num(item.confidence ?? 1))),
      words: words.filter((w) => w && typeof w.text === 'string' && w.text.trim()).map((w) => ({ text: w.text as string, box: box(w, width as number, height as number) })),
    })
  }
  return { width: width as number, height: height as number, lines }
}
