import { closestComponent, cleanRoom, findComponent, findCourse, findDates, findDays, findLoneTime, findSection, findSectionAndComponent, findTimeRange, sectionOfCell } from './fields'
import { CELL_BREAK, tokensOf, typicalHeight, visualLines } from './layout'
import type { RecognizedText } from './recognized'
import { readLines } from './blockReader'
import { readTables } from './tableReader'
import { STRUCTURE_CERTAINTY, issueFactor, type ColumnKind, type ParsedRow, type ParsedSchedule, type RawRow, type RowIssue } from './rows'

/** A recognition confidence below this is the reader saying it wasn't sure of the words. */
const UNSURE_BELOW = 0.45

/** Reads the fields of one class from the text of its cells, or null if nothing in it looks like a class. */
export function buildRow(raw: RawRow): ParsedRow | null {
  const cell = (kind: ColumnKind) =>
    (raw.cells.get(kind) ?? '')
      .replaceAll(CELL_BREAK, ' ')
      .replace(/\s+/g, ' ')
      .trim()
  const issues = new Set<RowIssue>()

  let timeText = raw.cells.get('daysTimes') ?? ''
  if (!timeText) timeText = raw.cells.get('times') ?? ''
  if (!timeText && (cell('start') || cell('end'))) timeText = `${cell('start')} - ${cell('end')}`
  const range = findTimeRange(timeText)
  const loneStart = range ? null : (findLoneTime(timeText)?.time ?? null)
  if (!range) issues.add('noTime')
  else if (range.certainty === 'guessed') issues.add('guessedTime')
  else if (range.certainty === 'repaired') issues.add('correctedText')

  const daysCell = cell('days')
  const daysMatch = daysCell ? findDays(daysCell) : findDays(timeText, range?.from ?? null)
  if (!daysMatch) issues.add('noDays')
  else if (daysMatch.certainty === 'guessed') issues.add('guessedDays')
  else if (daysMatch.certainty === 'repaired') issues.add('correctedText')

  const courseText = cell('course')
  const course = findCourse(courseText)
  if (!course) issues.add('noCourse')
  else if (course.certainty === 'guessed' || raw.guessedCourse) issues.add('guessedCourse')
  else if (course.certainty === 'repaired') issues.add('correctedText')
  if (!range && !daysMatch && !course) return null

  let title = cell('title')
  if (!title && course) {
    // a table's course line has its title after the code, and the dash between them is often not read at all
    const after = courseText.slice(course.to)
    title = raw.structure === 'table' ? after.replace(/^[\s-]+/, '').trim() : (/^\s*-\s+(\S.*)$/.exec(after)?.[1]?.trim() ?? '')
  }

  // a class number and its section read as one word ("2918301"): the number is the first five digits
  let section = sectionOfCell(cell('section')) ?? ''
  const fused = /^[0-9OolI|]{5}([0-9OolI|]{2}[A-Za-z]?)$/.exec(cell('nbr'))
  if (!section && fused) {
    section = sectionOfCell(fused[1]) ?? ''
    if (section) issues.add('splitText')
  }

  const componentCell = cell('component')
  let component = ''
  if (raw.structure === 'table') {
    component = closestComponent(componentCell) ?? findComponent(componentCell) ?? ''
    if (!section) section = findSection(courseText) ?? ''
  } else {
    const both = findSectionAndComponent(componentCell)
    component = both?.component ?? findComponent(componentCell) ?? ''
    section = both?.section ?? findSection(componentCell) ?? ''
  }
  if (!section && course) section = /^\s*-\s*(\d{2}[A-Z]?)(?![0-9:])/.exec(courseText.slice(course.to))?.[1] ?? ''

  const room = cleanRoom(cell('room'))
  if (!room) issues.add('noRoom')

  const dates = findDates(cell('dates'))
  if (dates.length < 2) issues.add('noDates')

  const lowest = raw.tokens.reduce((m, t) => Math.min(m, t.confidence), 1)
  if (lowest < UNSURE_BELOW) issues.add('unsureText')

  let confidence = STRUCTURE_CERTAINTY[raw.structure]
  for (const issue of issues) confidence *= issueFactor(issue)
  return {
    course: course?.code ?? '',
    title,
    section,
    component,
    days: daysMatch?.days ?? [],
    start: range?.start ?? loneStart,
    end: range?.end ?? null,
    location: room,
    startDate: dates.length >= 2 ? dates[0] : null,
    endDate: dates.length >= 2 ? dates[1] : null,
    confidence,
    issues,
  }
}

const loose = (text: string) => text.toLowerCase().replace(/[^a-z0-9]/g, '')
const sameClass = (r: ParsedRow) => [r.course, r.section, r.component, r.start, r.end, loose(r.location), r.startDate, r.endDate].join('|')

/** A class read twice is kept once, and a class listed with one row for each day is one class on several days. */
function mergeRepeats(rows: ParsedRow[], notes: string[]): ParsedRow[] {
  const merged: ParsedRow[] = []
  let repeats = 0
  for (const row of rows) {
    const i = merged.findIndex((m) => sameClass(m) === sameClass(row))
    if (i < 0) {
      merged.push(row)
      continue
    }
    const other = merged[i]
    if (row.days.every((d) => other.days.includes(d))) repeats++
    else if (row.days.every((d) => !other.days.includes(d))) {
      merged[i] = { ...other, days: [...other.days, ...row.days].sort((a, b) => a - b), confidence: Math.min(other.confidence, row.confidence), issues: new Set([...other.issues, ...row.issues]) }
    } else merged.push(row)
  }
  if (repeats > 0) notes.push(`Skipped ${repeats === 1 ? 'a class' : `${repeats} classes`} that appeared more than once.`)
  return merged
}

/** Turns text recognized in a picture of a class schedule into the classes it shows, each with how sure the reading is. */
export function parseSchedule(reading: RecognizedText): ParsedSchedule {
  const tokens = tokensOf(reading)
  if (!tokens.length) return { rows: [], notes: [], problem: 'noText' }
  const h = typicalHeight(tokens)
  const lines = visualLines(tokens, h)
  const notes: string[] = []
  let raw = readTables(lines, h, notes)
  if (!raw.length) raw = readLines(lines, h, notes)
  const rows = raw.map(buildRow).filter((r): r is ParsedRow => r !== null)
  const merged = mergeRepeats(rows, notes)
  return { rows: merged, notes, problem: merged.length ? null : 'noClasses' }
}
