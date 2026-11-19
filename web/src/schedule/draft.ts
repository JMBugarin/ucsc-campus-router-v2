import { DAY_CODES, clockFromHhmm } from './time'
import type { Meeting } from './meeting'

const tidy = (t: string) => t.split(/\s+/).filter(Boolean).join(' ')

/** A class being added, edited or checked after an import. Nothing is saved until the student says so. */
export interface ClassDraft {
  id: number
  course: string
  title: string
  section: string
  component: string
  classNbr: string
  days: number[]
  start: string | null
  end: string | null
  location: string
  startDate: string | null
  endDate: string | null
  /** why the import wasn't sure of this class, for the student */
  reasons: string[]
  edited: boolean
  skipDates?: string[]
}

let nextId = 1
export const newDraft = (patch: Partial<ClassDraft> = {}): ClassDraft => ({
  id: nextId++,
  course: '',
  title: '',
  section: '',
  component: '',
  classNbr: '',
  days: [],
  start: null,
  end: null,
  location: '',
  startDate: null,
  endDate: null,
  reasons: [],
  edited: false,
  ...patch,
})

export const draftFromMeeting = (m: Meeting): ClassDraft =>
  newDraft({ course: m.course, title: m.title, section: m.section, component: m.component, classNbr: m.class_nbr, days: [...m.days], start: m.start, end: m.end, location: m.location, startDate: m.start_date, endDate: m.end_date, skipDates: m.skip_dates })

export const flagged = (d: ClassDraft) => d.reasons.length > 0 && !d.edited
export const draftLabel = (d: ClassDraft) => [d.course, d.component].filter(Boolean).join(' ')
export const daysLabel = (d: ClassDraft) => d.days.map((x) => DAY_CODES[x]).join('')
export function draftTime(d: ClassDraft): string {
  if (!d.start && !d.end) return ''
  return `${d.start ? clockFromHhmm(d.start) : '?'}–${d.end ? clockFromHhmm(d.end) : '?'}`
}

/** What stops the class being saved, in words for the student, or null. */
export function problem(d: ClassDraft): string | null {
  if (!d.course.trim()) return 'Enter the course, like CSE 130.'
  if (!d.days.length) return 'Pick the days it meets.'
  if (!d.start || !d.end) return 'Pick a start and end time.'
  if (d.end <= d.start) return 'The end time must be after the start time.'
  if (!d.startDate || !d.endDate) return 'Pick the first and last dates.'
  if (d.endDate < d.startDate) return 'The last date is before the first.'
  if (tidy(d.course).length > 40 || tidy(d.title).length > 80 || tidy(d.section).length > 10 || tidy(d.component).length > 30 || tidy(d.location).length > 80) return 'Something here is too long to save. Shorten it.'
  return null
}

/** The class as it is saved. Only call when `problem` is null. */
export function toMeeting(d: ClassDraft): Meeting {
  const m: Meeting = {
    course: tidy(d.course),
    title: tidy(d.title),
    section: tidy(d.section),
    component: tidy(d.component),
    class_nbr: tidy(d.classNbr),
    days: [...d.days].sort((a, b) => a - b),
    start: d.start!,
    end: d.end!,
    location: tidy(d.location),
    start_date: d.startDate!,
    end_date: d.endDate!,
  }
  if (d.skipDates?.length) m.skip_dates = [...d.skipDates]
  return m
}
