import { cleanRoom, courseStatus, findComponent, findCourse, findDays, findLoneTime, findTimeRange, hasClock, looksLikeRoom } from './fields'
import { CELL_BREAK, type VisualLine } from './layout'
import { RawRow } from './rows'

const ROOM_LABELS = new Set(['room', 'location', 'where', 'building', 'place'])
const isRoomLabel = (text: string) => ROOM_LABELS.has(text.toLowerCase().replace(/[^a-z]/g, ''))
const unbreak = (s: string) => s.replaceAll(CELL_BREAK, ' ')

/** True if `next` carries on from `line`: a line ending with a time and a dash, and the next starting with the other time. */
function continues(line: VisualLine, next: VisualLine, h: number): boolean {
  if (next.top - line.bottom > 1.8 * h) return false
  const text = line.text.trimEnd()
  return text.endsWith('-') && hasClock(text) && hasClock(next.text)
}

/** A course line without its title, so a word in the title isn't taken for the kind of meeting. */
function withoutTitle(text: string): string {
  const course = findCourse(text)
  if (!course) return text
  const rest = text.slice(course.to)
  if (!/^\s*-\s+\S/.test(rest)) return text
  const words = rest
    .replace(/^\s*-\s+/, '')
    .trim()
    .split(/\s+/)
  return words.length <= 2 && findComponent(words.join(' ')) !== null ? text : text.slice(0, course.to)
}

class Page {
  readonly gap: number
  readonly taken = new Set<number>()
  lastCourse: string | null = null
  lastTimeLine = -100
  constructor(
    readonly lines: VisualLine[],
    readonly h: number,
    readonly notes: string[],
  ) {
    this.gap = 2.2 * h
  }

  /** The course for the time on line i: before the time, on a line above, or the one the class before had. */
  courseFor(i: number, before: string, used: VisualLine[]) {
    let text = before
    let between = ''
    let skipped = false
    let inherited = false
    const hasCourse = (s: string) => findCourse(unbreak(s)) !== null
    if (!hasCourse(before)) {
      for (let k = i - 1; k >= 0 && i - k <= 8; k--) {
        if (this.taken.has(k) || findTimeRange(this.lines[k].text)) break
        const found = findCourse(this.lines[k].text)
        if (!found) continue
        text = this.lines[k].textWithBreaks(this.gap)
        between = this.lines
          .slice(k + 1, i)
          .map((l) => l.text)
          .join(' ')
        used.push(this.lines[k])
        const status = courseStatus(this.lines.slice(k + 1, i).flatMap((l) => l.tokens.map((t) => t.text)))
        if (status !== 'enrolled') {
          this.notes.push(`Skipped ${found.code} (${status}).`)
          skipped = true
        }
        break
      }
      // a second time under the same course (`MWF ...` then `Th ...`) has no course line of its own
      if (!hasCourse(text) && this.lastCourse !== null && this.lastTimeLine >= 0 && i - this.lastTimeLine <= 3 && this.lines[i].top - this.lines[this.lastTimeLine].bottom <= 6 * this.h) {
        text = this.lastCourse
        inherited = true
      }
    }
    if (hasCourse(text)) this.lastCourse = text
    return { text, between, inherited, skipped }
  }

  /** The room for a time that ends on line `last`: in the cells after the time, under a `Room` label, or the line below. */
  roomFor(last: number, after: string, used: VisualLine[]): string {
    for (const cell of after.split(CELL_BREAK)) if (looksLikeRoom(cell)) return cleanRoom(cell)
    for (let j = last + 1; j < this.lines.length && j <= last + 6; j++) {
      const next = this.lines[j]
      if (next.top - this.lines[j - 1].bottom > 3 * this.h || findTimeRange(next.text)) break
      if (isRoomLabel(next.text)) {
        if (j + 1 < this.lines.length && !this.taken.has(j + 1) && looksLikeRoom(this.lines[j + 1].text)) {
          this.taken.add(j)
          this.taken.add(j + 1)
          used.push(this.lines[j + 1])
          return cleanRoom(this.lines[j + 1].text)
        }
        break
      }
      if (j === last + 1 && !this.taken.has(j) && next.top - this.lines[last].bottom <= 2.4 * this.h && looksLikeRoom(next.text)) {
        this.taken.add(j)
        used.push(next)
        return cleanRoom(next.text)
      }
    }
    return ''
  }
}

/**
 * Reads a class from every line that has a time range in it: a row of a table with no headings, a card whose course
 * is a line or two above its time and whose room is the line below, or a card that labels each field.
 */
export function readLines(lines: VisualLine[], h: number, notes: string[]): RawRow[] {
  const page = new Page(lines, h, notes)
  const rows: RawRow[] = []
  let skip = -1
  for (let i = 0; i < lines.length; i++) {
    if (i === skip) continue
    let text = lines[i].textWithBreaks(page.gap)
    const used: VisualLine[] = [lines[i]]
    let last = i
    let range = findTimeRange(text)
    if (!range && i + 1 < lines.length && continues(lines[i], lines[i + 1], h)) {
      text = `${text} ${lines[i + 1].textWithBreaks(page.gap)}`
      range = findTimeRange(text)
      if (range) {
        used.push(lines[i + 1])
        last = i + 1
        skip = last
      }
    }
    // a lone time (its partner was lost) still makes a class when days and a course are there
    const lone = range ? null : findLoneTime(text)
    if (!range && (!lone || !findDays(text))) continue
    const timeFrom = range?.from ?? lone!.from
    const timeTo = range?.to ?? lone!.to

    const before = text.slice(0, timeFrom)
    const course = page.courseFor(i, before, used)
    page.lastTimeLine = last
    page.taken.add(i)
    page.taken.add(last)
    if (course.skipped || (!range && !findCourse(unbreak(course.text)))) continue
    const room = page.roomFor(last, text.slice(timeTo), used)

    const head = withoutTitle(unbreak(course.text))
    const hint = unbreak(`${head} ${course.between} ${before}`)
    const row = new RawRow('lines')
    row.guessedCourse = course.inherited
    row.cells.set('course', unbreak(course.text))
    row.cells.set('component', hint)
    row.cells.set('section', hint)
    row.cells.set('daysTimes', text)
    row.cells.set('room', room)
    for (const l of used) row.tokens.push(...l.tokens)
    rows.push(row)
  }
  return rows
}
