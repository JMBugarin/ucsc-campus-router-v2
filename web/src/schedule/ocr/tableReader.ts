import { courseStatus, editDistance, findCourse, findDays } from './fields'
import { visualLines, type Token, type VisualLine } from './layout'
import { RawRow, type ColumnKind } from './rows'

interface Column {
  kind: ColumnKind
  left: number
  /** where the heading's last word ends, when the heading is more than one word */
  right?: number
  /** named by a word that could mean something else (`Class`) */
  weak?: boolean
}
interface Band {
  lines: VisualLine[]
  columns: Column[]
}
const bandTop = (b: Band) => Math.min(...b.lines.map((l) => l.top))

const KEYWORDS: [ColumnKind, string[]][] = [
  ['nbr', ['nbr', 'number']],
  ['section', ['section', 'sec']],
  ['component', ['component', 'type']],
  ['days', ['days', 'day']],
  ['times', ['times', 'time']],
  ['room', ['room', 'location', 'building', 'where', 'place']],
  ['instructor', ['instructor', 'professor', 'teacher', 'faculty']],
  ['course', ['course', 'code', 'subject']],
  ['title', ['title', 'name', 'description']],
  ['dates', ['dates', 'date']],
]

const word = (t: Token) => t.text.toLowerCase().replace(/[^a-z/#&]/g, '')
const is = (w: string, key: string) => w === key || (key.length >= 6 && w.length >= 5 && editDistance(w, key) <= 1)
function kindOfWord(w: string): ColumnKind | null {
  for (const [kind, keys] of KEYWORDS) if (keys.some((k) => is(w, k))) return kind
  return null
}
const isHeaderWord = (w: string) => w === 'class' || w === 'end' || w.startsWith('start') || kindOfWord(w) !== null

/** The columns a header row names, left to right, with the x position of each heading. */
function columnsOf(tokens: Token[], h: number): Column[] {
  const sorted = [...tokens].sort((a, b) => a.left - b.left)
  const words = sorted.map(word)
  const at = (j: number) => (j < words.length ? words[j] : null)
  const hasNbr = words.includes('nbr')
  const columns: Column[] = []
  for (let i = 0; i < sorted.length; i++) {
    const w = words[i]
    let kind: ColumnKind | null = null
    let consumed = 0
    if (w === 'days&times' || w === 'day&time') kind = 'daysTimes'
    else if (is(w, 'days') || w === 'day' || w === 'days&' || w === 'day&') {
      // `Days & Times` is often read with the ampersand stuck to the first word
      let j = i + 1
      if (!w.endsWith('&') && (at(j) === '&' || at(j) === 'and')) j++
      const next = at(j)
      if (next !== null && (is(next, 'times') || next === 'time')) {
        kind = 'daysTimes'
        consumed = j - i
      } else kind = 'days'
    } else if (w === 'class') {
      if (['nbr', '#', 'no', 'num', 'number'].includes(at(i + 1) ?? '')) {
        kind = 'nbr'
        consumed = 1
      } else if (!hasNbr) columns.push({ kind: 'course', left: sorted[i].left, weak: true })
    } else if (w.startsWith('start') && w.includes('/')) {
      kind = 'dates'
      if (at(i + 1) === 'date' || at(i + 1) === 'dates') consumed = 1
    } else if (w === 'start' && (at(i + 1) === '/' || at(i + 1) === '&') && at(i + 2) === 'end') {
      kind = 'dates'
      consumed = at(i + 3) === 'date' ? 3 : 2
    } else if (w === 'start') kind = 'start'
    else if (w === 'end' && columns.some((c) => c.kind === 'start')) kind = 'end'
    else kind = kindOfWord(w)
    if (kind !== null) columns.push({ kind, left: sorted[i].left, right: sorted[i + consumed].right })
    i += consumed
  }
  // `Class` just before `Section` and `Component` heads the class numbers, as it does on MyUCSC
  const section = columns.find((c) => c.kind === 'section')
  const named = new Set(columns.map((c) => c.kind))
  const seen = new Set<ColumnKind>()
  const result: Column[] = []
  for (const c of columns) {
    let column = c
    if (c.weak) {
      const classNumbers = !!section && named.has('component') && section.left - c.left < 14 * h
      if (section && section.left - c.left >= 14 * h) continue
      if (classNumbers) column = { kind: 'nbr', left: c.left }
    }
    if (!seen.has(column.kind)) {
      seen.add(column.kind)
      result.push(column)
    }
  }
  addMisreadRoom(result, sorted, h)
  return result
}

/** A `Room` heading read as something else (`Koom`) is still the one word between the times and the instructor. */
function addMisreadRoom(columns: Column[], headings: Token[], h: number) {
  if (columns.some((c) => c.kind === 'room')) return
  const timing = columns.filter((c) => c.kind === 'daysTimes' || c.kind === 'times' || c.kind === 'end')
  const instructor = columns.find((c) => c.kind === 'instructor')
  if (!timing.length || !instructor) return
  const after = Math.max(...timing.map((c) => c.right ?? c.left))
  const between = headings.filter((t) => t.left > after + 0.5 * h && t.right < instructor.left && word(t).length >= 3)
  if (between.length === 1) {
    columns.push({ kind: 'room', left: between[0].left })
    columns.sort((a, b) => a.left - b.left)
  }
}

/** A heading dropped or misread is where the same heading is in the page's other tables (MyUCSC draws one per course). */
function borrowColumns(bands: Band[], h: number) {
  const borrowed = bands.map(() => [] as Column[])
  for (let b = 0; b < bands.length; b++) {
    for (let o = 0; o < bands.length; o++) {
      if (o === b) continue
      const same = bands[b].columns.filter((c) => bands[o].columns.some((x) => x.kind === c.kind && Math.abs(x.left - c.left) <= 1.5 * h))
      if (same.length < 3) continue
      for (const x of bands[o].columns) {
        const present = bands[b].columns.some((c) => c.kind === x.kind || Math.abs(c.left - x.left) <= 1.5 * h)
        if (!present && !borrowed[b].some((c) => c.kind === x.kind)) borrowed[b].push(x)
      }
    }
  }
  for (let b = 0; b < bands.length; b++) {
    bands[b].columns.push(...borrowed[b])
    bands[b].columns.sort((a, c) => a.left - c.left)
  }
}

const TIMING_KINDS = new Set<ColumnKind>(['days', 'times', 'daysTimes', 'start'])

function leftmostHeading(line: VisualLine): number {
  const lefts = line.tokens.filter((t) => isHeaderWord(word(t))).map((t) => t.left)
  return lefts.length ? Math.min(...lefts) : Infinity
}

function findBands(lines: VisualLine[], h: number): Band[] {
  const marked = (l: VisualLine) => l.tokens.some((t) => isHeaderWord(word(t)))
  const bands: Band[] = []
  let i = 0
  while (i < lines.length) {
    if (!marked(lines[i])) {
      i++
      continue
    }
    let j = i
    // a heading's second line sits under the first; a line with a heading word further left is a menu beside the table
    let left = leftmostHeading(lines[i])
    while (j + 1 < lines.length && marked(lines[j + 1]) && lines[j + 1].top - lines[j].bottom <= 0.6 * h) {
      if (leftmostHeading(lines[j + 1]) < left - 2 * h) break
      left = Math.min(left, leftmostHeading(lines[j + 1]))
      j++
    }
    const group = lines.slice(i, j + 1)
    const columns = columnsOf(
      group.flatMap((l) => l.tokens),
      h,
    )
    const kinds = new Set(columns.map((c) => c.kind))
    if (kinds.size >= 3 && [...kinds].some((k) => TIMING_KINDS.has(k))) bands.push({ lines: group, columns })
    i = j + 1
  }
  return bands
}

const TITLE_START = /^[A-Z][A-Z&]{1,4}\s?\d{1,3}[A-Z]{0,2}\b/

/** The nearest line above a table's headings that starts with a course code (`XYZ 10 - Sample Calculus`). */
function titleAbove(lines: VisualLine[], band: Band, h: number): VisualLine | null {
  const top = bandTop(band)
  for (let k = lines.length - 1; k >= 0; k--) {
    const line = lines[k]
    if (line.bottom > top + 0.2 * h) continue
    if (top - line.bottom > 14 * h) return null
    if (TITLE_START.test(line.text)) return line
  }
  return null
}

const DATE_WORD = /^[0-9OolI|]{1,2}\/[0-9OolI|]{1,2}\/[0-9OolIsB]{4}-?$/
const CLOCK_WORD = /^-?[0-9OolI|]{0,2}[:.;][0-9OolI|SB]{2}([AaPp]\.?[Mm]\.?)?-?$/

/** The columns a word belongs in by what it says (a time, a day, a date), and how far it may be moved, in text heights. */
function typedKinds(text: string): { kinds: Set<ColumnKind>; reach: number } | null {
  if (text === '-') return { kinds: new Set(['daysTimes', 'times', 'start', 'end', 'dates']), reach: 15 }
  if (DATE_WORD.test(text)) return { kinds: new Set(['dates']), reach: 15 }
  if (CLOCK_WORD.test(text)) return { kinds: new Set(['daysTimes', 'times', 'start', 'end']), reach: 15 }
  const days = findDays(text)
  if (days && days.from === 0 && days.to === text.length && days.certainty !== 'guessed') {
    // a lone `R` is Thursday, and also the first word of `R Carson Acad`: only believed beside the times
    return { kinds: new Set(['daysTimes', 'days']), reach: text.length > 1 ? 15 : 3 }
  }
  return null
}

/** A room number read together with the next cell, sitting at the very edge of its own, goes back with the room. */
function moveRoomNumber(row: RawRow) {
  const room = row.cells.get('room')
  const next = row.cells.get('instructor')
  if (room === undefined || next === undefined || !room || /[0-9]/.test(room)) return
  const m = /^([A-Za-z]?[0-9]{1,4}[A-Za-z]?)(?:\s+(.*))?$/.exec(next)
  if (!m) return
  row.cells.set('room', `${room} ${m[1]}`)
  row.cells.set('instructor', m[2] ?? '')
}

const ID_TOKEN = /^[0-9OolI|]{4,9}[A-Za-z]?$/
const SECTION_TOKEN = /^[0-9OolI|]{2}[A-Za-z]?$/

/** The columns of one table, and which of them a word belongs to. */
class Table {
  constructor(
    readonly columns: Column[],
    readonly h: number,
  ) {}
  /** a word starts a little left of its heading as often as right of it */
  get tolerance() {
    return 1.5 * this.h
  }
  kindOf(t: Token): ColumnKind | null {
    const typed = typedKinds(t.text)
    if (typed) {
      let nearest: Column | null = null
      for (const c of this.columns) {
        const nearer = nearest === null || Math.abs(c.left - t.left) < Math.abs(nearest.left - t.left)
        if (typed.kinds.has(c.kind) && nearer) nearest = c
      }
      if (nearest && Math.abs(nearest.left - t.left) <= typed.reach * this.h) return nearest.kind
    }
    let found: ColumnKind | null = null
    for (const c of this.columns) if (t.left >= c.left - this.tolerance) found = c.kind
    return found
  }
}

/** A misread `Class Nbr` heading leaves the class numbers without a column: they are the numbers just left of Section. */
function addClassNumbers(columns: Column[], region: VisualLine[], h: number) {
  const section = columns.find((c) => c.kind === 'section')
  if (!section || columns.some((c) => c.kind === 'nbr')) return
  const lefts = region.flatMap((l) => l.tokens.filter((t) => ID_TOKEN.test(t.text) && t.left < section.left - 1.5 * h && t.left > section.left - 12 * h).map((t) => t.left))
  if (!lefts.length) return
  columns.push({ kind: 'nbr', left: Math.min(...lefts) })
  columns.sort((a, b) => a.left - b.left)
}

/** One word for each class: its class number or section, or, for a table with a course column, its course. */
function rowAnchors(region: VisualLine[], table: Table): Token[] {
  const byCourse = table.columns.some((c) => c.kind === 'course') && !table.columns.some((c) => c.kind === 'nbr')
  const anchors: Token[] = []
  for (const line of region) {
    if (byCourse) {
      const cell = line.tokens.filter((t) => table.kindOf(t) === 'course')
      if (cell.length && findCourse(cell.map((t) => t.text).join(' '))) anchors.push(cell[0])
      continue
    }
    for (const t of line.tokens) {
      const kind = table.kindOf(t)
      if (kind === 'nbr' && ID_TOKEN.test(t.text)) anchors.push(t)
      if (kind === 'section' && SECTION_TOKEN.test(t.text)) anchors.push(t)
    }
  }
  anchors.sort((a, b) => a.centerY - b.centerY)
  const rows: Token[] = []
  for (const a of anchors) {
    if (rows.length && Math.abs(a.centerY - rows[rows.length - 1].centerY) <= 0.9 * table.h) {
      if (table.kindOf(a) === 'nbr') rows[rows.length - 1] = a
      continue
    }
    rows.push(a)
  }
  return rows
}

function readBand(lines: VisualLine[], band: Band, title: VisualLine | null, limit: number, h: number, notes: string[]): RawRow[] {
  const hasRowKey = band.columns.some((c) => c.kind === 'nbr' || c.kind === 'section' || c.kind === 'course')
  if (!hasRowKey) return []
  const top = bandTop(band)
  if (title) {
    const status = courseStatus(lines.filter((l) => l.top >= title.bottom - 1 && l.bottom <= top + 1).flatMap((l) => l.tokens.map((t) => t.text)))
    if (status !== 'enrolled') {
      notes.push(`Skipped ${findCourse(title.text)?.code ?? 'a course'} (${status}).`)
      return []
    }
  }
  const lastHeading = band.lines[band.lines.length - 1]
  const region = lines.filter((l) => l.centerY > lastHeading.centerY + 0.6 * h && l.top < limit)
  const columns = [...band.columns]
  addClassNumbers(columns, region, h)
  const table = new Table(columns, h)
  const anchors = rowAnchors(region, table)
  if (!anchors.length) return []

  // the words of a wrapping cell are above and below the class number, so each word goes to the nearest row
  const reach = 2.6 * h
  const cells = anchors.map(() => new Map<ColumnKind, Token[]>())
  const used = anchors.map(() => [] as Token[])
  for (const line of region) {
    for (const t of line.tokens) {
      const kind = table.kindOf(t)
      if (kind === null) continue
      let nearest = 0
      for (let k = 1; k < anchors.length; k++) if (Math.abs(anchors[k].centerY - t.centerY) < Math.abs(anchors[nearest].centerY - t.centerY)) nearest = k
      if (Math.abs(anchors[nearest].centerY - t.centerY) > reach) continue
      const list = cells[nearest].get(kind) ?? []
      cells[nearest].set(kind, list)
      list.push(t)
      used[nearest].push(t)
    }
  }
  return anchors.map((_, k) => {
    const row = new RawRow('table')
    row.tokens.push(...used[k])
    for (const [kind, toks] of cells[k])
      row.cells.set(
        kind,
        visualLines(toks, h)
          .map((l) => l.text)
          .join(' '),
      )
    if (title) row.cells.set('course', title.text)
    moveRoomNumber(row)
    return row
  })
}

/**
 * Reads tables whose columns are named in a header row, with a row for each class. Words go to the column whose
 * heading they sit under and to the nearest row, so cells that wrap, or were read with a neighbour, still land right.
 */
export function readTables(lines: VisualLine[], h: number, notes: string[]): RawRow[] {
  const bands = findBands(lines, h)
  borrowColumns(bands, h)
  const titles = bands.map((band) => (band.columns.some((c) => c.kind === 'course') ? null : titleAbove(lines, band, h)))
  return bands.flatMap((band, b) => readBand(lines, band, titles[b], b + 1 < bands.length ? (titles[b + 1]?.top ?? bandTop(bands[b + 1])) - 0.2 * h : Infinity, h, notes))
}
