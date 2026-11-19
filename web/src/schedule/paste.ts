import type { Campus } from './campus'
import { DAY_CODES } from './time'
import { MAX_PASTED_CHARS, ScheduleError, cleanMeeting, type Meeting } from './meeting'

const COURSE = /(?<course>[A-Z][A-Z&]{1,5} \d{1,3}[A-Z]{0,2}) - (?<title>.+?) Status Units/g
const STATUS = /Status Units Grading Grade Deadlines (?<status>Enrolled|Dropped|Waiting|Wait Listed)/g
const ROW =
  /(?<nbr>\d{4,5}) (?<section>\d{2}[A-Z]?) (?<component>[A-Za-z]+) (?<days>(?:Mo|Tu|We|Th|Fr|Sa|Su)+) (?<t1>\d{1,2}:\d{2}\s?[AP]M) ?[-–—]? ?(?<t2>\d{1,2}:\d{2}\s?[AP]M) (?<rest>.*?)\s*(?<d1>\d{2}\/\d{2}\/\d{4}) ?- ?(?<d2>\d{2}\/\d{2}\/\d{4})/g
const ROW_START = /\b\d{4,5} \d{2}[A-Z]? (?:Lecture|Discussion|Laboratory|Lab|Seminar|Studio|Section)\b/g

class FormatProblem extends Error {}

function to24h(text: string): string {
  const m = /^(\d{1,2}):(\d{2})([AP]M)$/.exec(text.replaceAll(' ', ''))
  const hour = m ? +m[1] : 0
  const minute = m ? +m[2] : 99
  if (!m || hour < 1 || hour > 12 || minute > 59) throw new FormatProblem(`'${text}' isn't a time`)
  return `${String((hour % 12) + (m[3] === 'PM' ? 12 : 0)).padStart(2, '0')}:${m[2]}`
}

function usDate(text: string): string {
  const [mo, d, y] = text.split('/')
  const t = new Date(Date.UTC(+y, +mo - 1, +d))
  if (t.getUTCFullYear() !== +y || t.getUTCMonth() !== +mo - 1 || t.getUTCDate() !== +d) throw new FormatProblem(`'${text}' isn't a date`)
  return `${y}-${mo}-${d}`
}

/**
 * Reads a schedule copied from MyUCSC's Class Schedule page. Line breaks don't matter. Dropped and
 * wait-listed courses are left out, and a row that looks like a class but can't be read is named in the notes.
 */
export function parsePasted(text: string, campus: Campus): { meetings: Meeting[]; notes: string[] } {
  if (!text.trim()) throw new ScheduleError('paste your schedule first')
  if (text.length > MAX_PASTED_CHARS) throw new ScheduleError('that text is too long to be a schedule')
  const flat = text.split(/\s+/).filter(Boolean).join(' ')
  const headers = [...flat.matchAll(COURSE)]
  const statuses = [...flat.matchAll(STATUS)]
  const meetings: Meeting[] = []
  const notes: string[] = []
  const claimed: [number, number][] = []

  for (const m of flat.matchAll(ROW)) {
    const g = m.groups!
    const start = m.index!
    claimed.push([start, start + m[0].length])
    const before = headers.filter((h) => h.index! < start)
    const head = before[before.length - 1]
    const course = head ? head.groups!.course : `Class ${g.nbr}`
    const title = head ? head.groups!.title : ''
    let status = 'Enrolled'
    if (head) {
      const after = statuses.filter((s) => s.index! > head.index! && s.index! < start)
      if (after.length) status = after[after.length - 1].groups!.status
    }
    if (status !== 'Enrolled') {
      notes.push(`Skipped ${course} (${status.toLowerCase()}).`)
      continue
    }
    const [location] = campus.splitLocation(g.rest)
    try {
      const days: number[] = []
      for (let i = 0; i < g.days.length; i += 2) days.push(DAY_CODES.indexOf(g.days.slice(i, i + 2)))
      meetings.push(
        cleanMeeting({
          course,
          title,
          section: g.section,
          component: g.component,
          class_nbr: g.nbr,
          days,
          start: to24h(g.t1),
          end: to24h(g.t2),
          location,
          start_date: usDate(g.d1),
          end_date: usDate(g.d2),
        }),
      )
    } catch (e) {
      if (e instanceof ScheduleError) notes.push(`Couldn't read ${course} ${g.component}: ${e.message}.`)
      else if (e instanceof FormatProblem) notes.push(`Couldn't read ${course} ${g.component}: a time or date isn't valid.`)
      else throw e
    }
  }
  for (const m of flat.matchAll(ROW_START)) {
    if (!claimed.some(([a, b]) => a <= m.index! && m.index! < b)) notes.push(`Couldn't read a row starting "${flat.slice(m.index!, Math.min(flat.length, m.index! + 50))}".`)
  }
  if (!meetings.length && !notes.length) notes.push("I couldn't find any classes in that text. Copy the whole Class Schedule page, or add classes by hand.")
  return { meetings, notes }
}
