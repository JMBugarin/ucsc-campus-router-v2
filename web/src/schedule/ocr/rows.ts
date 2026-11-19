import type { Token } from './layout'

/** What a column of a schedule table, or a part of a card, holds. */
export type ColumnKind = 'nbr' | 'course' | 'title' | 'section' | 'component' | 'days' | 'times' | 'daysTimes' | 'start' | 'end' | 'room' | 'instructor' | 'dates'

/** Where a row's words were found: under the headings of a table (surer), or among lines of text. */
export type Structure = 'table' | 'lines'
export const STRUCTURE_CERTAINTY: Record<Structure, number> = { table: 1.0, lines: 0.92 }

/** The words of one class, as text for each field, before the fields are read. */
export class RawRow {
  readonly cells = new Map<ColumnKind, string>()
  readonly tokens: Token[] = []
  /** the course was taken from the class before, because this one has none of its own */
  guessedCourse = false
  constructor(readonly structure: Structure) {}
}

export type Severity = 'info' | 'note' | 'check' | 'missing'
const SEVERITY_FACTOR: Record<Severity, number> = { info: 1.0, note: 0.97, check: 0.8, missing: 0.6 }
const SEVERITY_INDEX: Record<Severity, number> = { info: 0, note: 1, check: 2, missing: 3 }

export const ROW_ISSUES = {
  unsureText: ['Some of this was hard to read.', 'check'],
  correctedText: ['Some characters were corrected.', 'note'],
  guessedDays: ['The days may be wrong.', 'check'],
  guessedTime: ['AM or PM was guessed.', 'check'],
  guessedCourse: ['The course may be wrong.', 'check'],
  splitText: ['Two columns were read as one.', 'note'],
  noCourse: ['No course was found.', 'missing'],
  noDays: ['No days were found.', 'missing'],
  noTime: ['No time was found.', 'missing'],
  noRoom: ['No room was found.', 'note'],
  noDates: ['No dates were found.', 'info'],
} as const satisfies Record<string, readonly [string, Severity]>
export type RowIssue = keyof typeof ROW_ISSUES

export const issueFactor = (i: RowIssue) => SEVERITY_FACTOR[ROW_ISSUES[i][1]]

/** A row with less confidence than this is flagged for the student to check. */
export const REVIEW_THRESHOLD = 0.85

/** One class read from a picture; anything the picture did not show is empty or null. */
export interface ParsedRow {
  course: string
  title: string
  section: string
  component: string
  days: number[]
  start: string | null
  end: string | null
  location: string
  startDate: string | null
  endDate: string | null
  confidence: number
  issues: Set<RowIssue>
}

export const needsReview = (r: ParsedRow) => r.confidence < REVIEW_THRESHOLD

/** What is missing or wrong, for the student, worst first. */
export function reasons(r: ParsedRow): string[] {
  return [...r.issues]
    .sort((a, b) => SEVERITY_INDEX[ROW_ISSUES[b][1]] - SEVERITY_INDEX[ROW_ISSUES[a][1]])
    .filter((i) => ROW_ISSUES[i][1] !== 'info')
    .map((i) => ROW_ISSUES[i][0])
}

export type ReadProblem = 'noText' | 'noClasses'
export interface ParsedSchedule {
  rows: ParsedRow[]
  notes: string[]
  problem: ReadProblem | null
}
