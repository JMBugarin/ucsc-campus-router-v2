import { Box, type RecognizedLine, type RecognizedText } from './recognized'

export class PictureError extends Error {}

const base = import.meta.env.BASE_URL
const MAX_SIDE = 2600
const MIN_WIDTH = 1000

/** Draws the picture at a size the reader handles well: big photos shrink, small screenshots grow. */
async function prepare(file: Blob): Promise<HTMLCanvasElement> {
  let bitmap: ImageBitmap
  try {
    bitmap = await createImageBitmap(file)
  } catch {
    throw new PictureError("That file isn't a picture I can read. Try a screenshot or a photo.")
  }
  const long = Math.max(bitmap.width, bitmap.height)
  const scale = long > MAX_SIDE ? MAX_SIDE / long : bitmap.width < MIN_WIDTH ? Math.min(2, 1600 / bitmap.width) : 1
  const canvas = document.createElement('canvas')
  canvas.width = Math.max(1, Math.round(bitmap.width * scale))
  canvas.height = Math.max(1, Math.round(bitmap.height * scale))
  const ctx = canvas.getContext('2d')
  if (!ctx) throw new PictureError("This browser can't read pictures. Paste your schedule instead.")
  ctx.drawImage(bitmap, 0, 0, canvas.width, canvas.height)
  bitmap.close?.()
  return canvas
}

interface TBox {
  x0: number
  y0: number
  x1: number
  y1: number
}
const box = (b: TBox) => new Box(b.x0, b.y0, b.x1, b.y1)

/**
 * Reads the text in a picture in this browser with Tesseract (served from this site; the picture is never uploaded),
 * in the same shape the phone app gets from Apple's Vision framework.
 */
export async function recognizePicture(file: Blob, onProgress: (p: number) => void = () => {}, signal?: AbortSignal): Promise<RecognizedText> {
  const canvas = await prepare(file)
  const { createWorker, OEM, PSM } = await import('tesseract.js')
  const worker = await createWorker('eng', OEM.LSTM_ONLY, {
    workerPath: `${base}tesseract/worker.min.js`,
    corePath: `${base}tesseract/`,
    langPath: `${base}tesseract/`,
    gzip: true,
    workerBlobURL: false,
    logger: (m) => m.status === 'recognizing text' && onProgress(m.progress),
  }).catch(() => {
    throw new PictureError("The picture reader couldn't start. Check your connection and try again.")
  })
  const stop = () => void worker.terminate()
  signal?.addEventListener('abort', stop)
  try {
    await worker.setParameters({ tessedit_pageseg_mode: PSM.SPARSE_TEXT, preserve_interword_spaces: '1' })
    const { data } = await worker.recognize(canvas, {}, { blocks: true, text: false })
    if (signal?.aborted) throw new PictureError('Stopped.')
    const lines: RecognizedLine[] = []
    for (const block of data.blocks ?? [])
      for (const para of block.paragraphs)
        for (const line of para.lines) {
          const text = line.text.replace(/\s+/g, ' ').trim()
          if (!text) continue
          lines.push({ text, box: box(line.bbox), confidence: Math.max(0, Math.min(1, line.confidence / 100)), words: line.words.filter((w) => w.text.trim()).map((w) => ({ text: w.text.trim(), box: box(w.bbox) })) })
        }
    return { width: canvas.width, height: canvas.height, lines }
  } catch (e) {
    if (e instanceof PictureError) throw e
    throw new PictureError("I couldn't read that picture. Try a clearer screenshot.")
  } finally {
    signal?.removeEventListener('abort', stop)
    void worker.terminate().catch(() => {})
  }
}
