/**
 * Readers for the fields of a class (days, times, course, room, dates) in text recognized from a picture.
 * Each repairs the mistakes recognition makes in that kind of field and says how sure it is of the result.
 * A port of the phone app's fields.dart.
 */
export type Certainty = 'exact' | 'repaired' | 'guessed'
const RANK: Record<Certainty, number> = { exact: 0, repaired: 1, guessed: 2 }
export const orWorse = (a: Certainty, b: Certainty): Certainty => (RANK[a] >= RANK[b] ? a : b)

export const normalizeText = (text: string) =>
  text
    .replace(/[‐-―−]/g, '-')
    .replaceAll(' ', ' ')
    .replace(/\s+/g, ' ')
    .trim()

const DIGITISH: Record<string, string> = { O: '0', o: '0', Q: '0', D: '0', l: '1', I: '1', '|': '1', i: '1', S: '5', B: '8', Z: '2' }
export const fixDigits = (text: string) =>
  text
    .split('')
    .map((c) => DIGITISH[c] ?? c)
    .join('')
const hasConfusable = (text: string) => /[^0-9]/.test(text)
export const tryInt = (s: string): number | null => (/^[+-]?\d+$/.test(s) ? parseInt(s, 10) : null)

// ---- times ----------------------------------------------------------------------------------------------------

export interface TimeRange {
  start: string
  end: string
  certainty: Certainty
  from: number
  to: number
}

const HOUR = '(?:[0-9][0-9OolI|]?|[OolI|][0-9]|[lI|])'
const MINUTE = '[0-9OolI|SB]{2}'
const CLOCK_WITH_COLON = new RegExp(`(?<![A-Za-z0-9])(${HOUR})\\s*([:.;])\\s*(${MINUTE})(?![0-9])(?:\\s*([AaPp])\\.?\\s*[Mm]\\b\\.?)?`, 'g')
const CLOCK_WITHOUT_COLON = /(?<![A-Za-z0-9:.;])([0-9]{1,2})\s*([AaPp])\.?\s*[Mm]\b\.?/g
const RANGE_SEPARATOR = /^[\s~_.|,;‖]*(?:[-‐-―−]+|to|until|thru|through)?[\s~_.|,;‖]*$/i

interface Clock {
  hour: number
  minute: number
  pm: boolean | null
  padded: boolean
  repaired: boolean
  from: number
  to: number
}
const minutesOf = (c: Clock, isPm: boolean) => ((c.hour % 12) + (isPm ? 12 : 0)) * 60 + c.minute

function clocks(text: string): Clock[] {
  const found: Clock[] = []
  for (const m of text.matchAll(CLOCK_WITH_COLON)) {
    const hourText = m[1]
    const minuteText = m[3]
    const hour = tryInt(fixDigits(hourText))
    const minute = tryInt(fixDigits(minuteText))
    if (hour === null || minute === null || minute > 59 || hour > 24) continue
    const meridiem = m[4]
    // a dot or semicolon for the colon is only believed beside AM or PM: `5.50` is a price or a mark, not a time
    if (m[2] !== ':' && meridiem === undefined) continue
    found.push({ hour, minute, pm: meridiem === undefined ? null : meridiem.toLowerCase() === 'p', padded: hourText.length === 2 && hourText.startsWith('0'), repaired: hasConfusable(hourText) || hasConfusable(minuteText), from: m.index!, to: m.index! + m[0].length })
  }
  for (const m of text.matchAll(CLOCK_WITHOUT_COLON)) {
    const from = m.index!
    const to = from + m[0].length
    if (found.some((c) => from < c.to && c.from < to)) continue
    const hour = parseInt(m[1], 10)
    if (hour < 1 || hour > 12) continue
    found.push({ hour, minute: 0, pm: m[2].toLowerCase() === 'p', padded: false, repaired: false, from, to })
  }
  return found.sort((a, b) => a.from - b.from)
}

const hhmm = (minutes: number) => `${String(Math.floor(minutes / 60)).padStart(2, '0')}:${String(minutes % 60).padStart(2, '0')}`

/** The first start and end time in `text`, such as `8:00AM - 9:05AM`, `1:20-2:25 PM` or `13:20 - 14:25`. */
export function findTimeRange(text: string): TimeRange | null {
  const cs = clocks(text)
  for (let i = 0; i + 1 < cs.length; i++) {
    const a = cs[i]
    const b = cs[i + 1]
    if (!RANGE_SEPARATOR.test(text.slice(a.to, b.from))) continue
    const range = resolveRange(a, b)
    if (range) return range
  }
  return null
}

function resolveRange(a: Clock, b: Clock): TimeRange | null {
  let certainty: Certainty = a.repaired || b.repaired ? 'repaired' : 'exact'
  let start: number
  let end: number
  if (a.pm === null && b.pm === null) {
    const twentyFour = a.hour > 12 || b.hour > 12 || a.hour === 0 || b.hour === 0 || a.padded || b.padded
    if (twentyFour) {
      start = a.hour * 60 + a.minute
      end = b.hour * 60 + b.minute
    } else {
      const schoolDayPm = (hour: number) => hour === 12 || hour < 8
      start = minutesOf(a, schoolDayPm(a.hour))
      end = minutesOf(b, schoolDayPm(b.hour))
      certainty = 'guessed'
    }
  } else {
    let aPm = a.pm ?? b.pm!
    let bPm = b.pm ?? a.pm!
    if (a.hour < 1 || a.hour > 12 || b.hour < 1 || b.hour > 12) return null
    if (a.pm === null && minutesOf(a, aPm) >= minutesOf(b, bPm)) aPm = !aPm
    if (b.pm === null && minutesOf(b, bPm) <= minutesOf(a, aPm)) bPm = !bPm
    if (a.pm === null || b.pm === null) certainty = orWorse(certainty, 'repaired')
    start = minutesOf(a, aPm)
    end = minutesOf(b, bPm)
  }
  const length = end - start
  if (start < 0 || end >= 24 * 60 || length < 10 || length > 14 * 60) return null
  return { start: hhmm(start), end: hhmm(end), certainty, from: a.from, to: b.to }
}

export const hasClock = (text: string) => clocks(text).length > 0

export interface LoneTime {
  time: string
  from: number
  to: number
}

/** The only time in `text`, or null if there is none or more than one. With no AM or PM it is guessed from school hours. */
export function findLoneTime(text: string): LoneTime | null {
  const cs = clocks(text)
  if (cs.length !== 1) return null
  const c = cs[0]
  const twentyFour = c.hour > 12 || c.hour === 0 || c.padded
  if (c.pm === null && !twentyFour) {
    const pm = c.hour === 12 || c.hour < 8
    return { time: hhmm(minutesOf(c, pm)), from: c.from, to: c.to }
  }
  if (c.pm !== null && (c.hour < 1 || c.hour > 12)) return null
  const minutes = c.pm === null ? c.hour * 60 + c.minute : minutesOf(c, c.pm)
  if (minutes >= 24 * 60) return null
  return { time: hhmm(minutes), from: c.from, to: c.to }
}

// ---- days -----------------------------------------------------------------------------------------------------

export interface DaysMatch {
  days: number[]
  certainty: Certainty
  from: number
  to: number
}

const DAY_NAMES: Record<string, number> = { monday: 0, mon: 0, tuesday: 1, tues: 1, tue: 1, wednesday: 2, wed: 2, thursday: 3, thurs: 3, thur: 3, thu: 3, friday: 4, fri: 4, saturday: 5, sat: 5, sunday: 6, sun: 6 }
const DAY_CODES: Record<string, number> = { mo: 0, tu: 1, we: 2, th: 3, fr: 4, sa: 5, su: 6 }
const DAY_LETTERS: Record<string, number> = { M: 0, T: 1, W: 2, R: 3, F: 4, S: 5, U: 6 }
const MISREAD_CODES: Record<string, number> = { m0: 0, tn: 3 }
// a day code whose first letter was lost: the second letters that belong to only one day
const LOST_FIRST_LETTER: Record<string, number> = { o: 0, e: 2, h: 3, r: 4, a: 5 }
const has = (o: Record<string, number>, k: string) => Object.prototype.hasOwnProperty.call(o, k)

function dayWord(raw: string): [number[], Certainty] | null {
  const word = raw.replace(/[.,;:]+$/, '')
  if (!word || word.length > 14) return null
  const lower = word.toLowerCase()
  if (has(DAY_NAMES, lower)) return [[DAY_NAMES[lower]], 'exact']
  if (!/^[A-Za-z0]+$/.test(word)) return null
  const upper = word === word.toUpperCase()
  const days: number[] = []
  let certainty: Certainty = 'exact'
  let i = 0
  while (i < word.length) {
    const pair = i + 1 < word.length ? word.slice(i, i + 2).toLowerCase() : ''
    if (pair && has(DAY_CODES, pair)) {
      days.push(DAY_CODES[pair])
      if (!upper && word[i] !== word[i].toUpperCase()) certainty = 'guessed'
      i += 2
    } else if (pair && has(MISREAD_CODES, pair)) {
      days.push(MISREAD_CODES[pair])
      certainty = orWorse(certainty, 'repaired')
      i += 2
    } else if (has(DAY_LETTERS, word[i])) {
      days.push(DAY_LETTERS[word[i]])
      i += 1
    } else if (i === word.length - 1 && days.length && has(LOST_FIRST_LETTER, word[i])) {
      days.push(LOST_FIRST_LETTER[word[i]])
      certainty = 'guessed'
      i += 1
    } else return null
  }
  if (new Set(days).size !== days.length) return null
  return [days, certainty]
}

const SHORT_DAY_NAMES = ['mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun']

/** A three letter word that is one letter off exactly one short day name (`Wea` for `Wed`). */
function misreadShortName(word: string): [number[], Certainty] | null {
  if (word.length !== 3 || has(DAY_NAMES, word)) return null
  const near: number[] = []
  for (let d = 0; d < 7; d++) if (editDistance(word, SHORT_DAY_NAMES[d]) === 1) near.push(d)
  return near.length === 1 ? [near, 'guessed'] : null
}

const WORD_SPAN = /[^\s,/&•·●○◦▪▫■□|]+/g
const DAY_JOINER = /^(?:\s|,|\/|&|and)*$/i

/** The group of weekdays in `text` nearest to character `near` (the first if null): `MWF`, `TuTh`, `MoWeFr`, `M W F`, `Mon, Wed`. */
export function findDays(text: string, near?: number | null): DaysMatch | null {
  const groups: DaysMatch[] = []
  let from: number | null = null
  let to: number | null = null
  let days: number[] = []
  let certainty: Certainty = 'exact'
  let namedStyle = false
  const close = () => {
    if (from !== null && days.length && new Set(days).size === days.length) groups.push({ days: [...days].sort((a, b) => a - b), certainty, from, to: to! })
    from = null
    days = []
    certainty = 'exact'
    namedStyle = false
  }
  for (const m of text.matchAll(WORD_SPAN)) {
    const word = m[0]
    if (from !== null && word.toLowerCase() === 'and') continue
    const bare = word.replace(/[.,;:]+$/, '').toLowerCase()
    // in a list of day names a word one letter off a short name is that name (`Mon, Wea, Fri`), not two codes
    const parsed = (from !== null && namedStyle ? misreadShortName(bare) : null) ?? dayWord(word)
    if (has(DAY_NAMES, bare)) namedStyle = true
    if (!parsed) {
      close()
      continue
    }
    if (from !== null && !DAY_JOINER.test(text.slice(to!, m.index!))) close()
    from ??= m.index!
    to = m.index! + word.length
    days.push(...parsed[0])
    certainty = orWorse(certainty, parsed[1])
  }
  close()
  if (!groups.length) return null
  if (near === null || near === undefined) return groups[0]
  const gap = (g: DaysMatch) => (near < g.from ? g.from - near : near > g.to ? near - g.to : 0)
  return groups.reduce((best, g) => (gap(g) < gap(best) ? g : best))
}

// ---- courses, sections, components ----------------------------------------------------------------------

export interface CourseMatch {
  code: string
  certainty: Certainty
  from: number
  to: number
}

const COURSE_CODE = /(?<![A-Za-z0-9])([A-Z][A-Z&]{1,4})\s?([0-9]{1,3}[A-Z]{0,2})(?![A-Za-z0-9])/
const NUMBER_ENDING_IN_O = /^([0-9]{1,2})(O{1,2})$/
const COURSE_CODE_MISREAD = /^\s*([A-Z]{2,5}?)\s?([OIl]{1,3})(?![A-Za-z0-9])/

/** The first course code in `text` (`CSE 101`, `MATH 19A`, `BME 160L`). */
export function findCourse(text: string): CourseMatch | null {
  const m = COURSE_CODE.exec(text)
  if (m) {
    // no course number ends in the letter O, so `2O` is `20`
    const zeros = NUMBER_ENDING_IN_O.exec(m[2])
    if (zeros) return { code: `${m[1]} ${zeros[1]}${'0'.repeat(zeros[2].length)}`, certainty: 'repaired', from: m.index, to: m.index + m[0].length }
    return { code: `${m[1]} ${m[2]}`, certainty: 'exact', from: m.index, to: m.index + m[0].length }
  }
  // `BIOLI`: a capital I read at the end is really the digit 1, as in `BIOL 1`
  const misread = COURSE_CODE_MISREAD.exec(text)
  const number = misread ? tryInt(fixDigits(misread[2])) : null
  if (!misread || number === null || number < 1) return null
  return { code: `${misread[1]} ${number}`, certainty: 'guessed', from: misread.index, to: misread.index + misread[0].length }
}

const COMPONENTS: Record<string, string> = {
  lecture: 'Lecture',
  lec: 'Lecture',
  lect: 'Lecture',
  discussion: 'Discussion',
  disc: 'Discussion',
  dis: 'Discussion',
  laboratory: 'Laboratory',
  lab: 'Laboratory',
  seminar: 'Seminar',
  sem: 'Seminar',
  studio: 'Studio',
  tutorial: 'Tutorial',
  recitation: 'Recitation',
}
const component = (w: string) => (Object.prototype.hasOwnProperty.call(COMPONENTS, w) ? COMPONENTS[w] : null)

/** The kind of meeting named in `text`, in the words the schedule page uses (`Lecture`, `Discussion`). */
export function findComponent(text: string): string | null {
  for (const m of text.matchAll(/[A-Za-z]+/g)) {
    const c = component(m[0].toLowerCase())
    if (c) return c
  }
  return null
}

/** How many single-character edits turn `a` into `b`. */
export function editDistance(a: string, b: string): number {
  let previous = Array.from({ length: b.length + 1 }, (_, j) => j)
  for (let i = 1; i <= a.length; i++) {
    const row = [i, ...new Array<number>(b.length).fill(0)]
    for (let j = 1; j <= b.length; j++) {
      const change = previous[j - 1] + (a[i - 1] === b[j - 1] ? 0 : 1)
      row[j] = Math.min(change, previous[j] + 1, row[j - 1] + 1)
    }
    previous = row
  }
  return previous[b.length]
}

/** The component a table cell most likely holds, even if a letter was misread (`Lectre`), or null. */
export function closestComponent(cell: string): string | null {
  const word = cell.trim().toLowerCase()
  if (word.length < 3) return null
  const exact = component(word)
  if (exact) return exact
  let best: string | null = null
  let bestDistance = 3
  for (const [key, value] of Object.entries(COMPONENTS)) {
    if (key.length < 6) continue
    const distance = editDistance(word, key)
    if (distance < bestDistance && distance <= Math.floor(key.length / 4)) {
      best = value
      bestDistance = distance
    }
  }
  return best
}

/** `enrolled`, `dropped` or `waitlisted`, from the words near a course's title. A letter of the word may be misread. */
export function courseStatus(words: Iterable<string>): string {
  for (const raw of words) {
    const w = raw.toLowerCase().replace(/[^a-z]/g, '')
    if (w.length < 4) continue
    if (w === 'wait' || w === 'waiting' || (w.length >= 8 && editDistance(w, 'waitlisted') <= 1)) return 'waitlisted'
    if (w.length >= 6 && editDistance(w, 'dropped') <= 1) return 'dropped'
    if (w.length >= 6 && editDistance(w, 'enrolled') <= 2) return 'enrolled'
  }
  return 'enrolled'
}

/** A section such as `01` or `01A` that is the whole of `cell`, after repairing letters read as digits. */
export function sectionOfCell(cell: string): string | null {
  // a stray O or 0 in front (`O01A`) is noise
  const m = /^(?:[Oo0](?=[0-9OoQDIl|]{2}[A-Za-z]$))?([0-9OoQDIl|]{2})([A-Za-z]?)$/.exec(cell.trim())
  if (!m) return null
  const digits = fixDigits(m[1])
  return tryInt(digits) === null ? null : `${digits}${m[2].toUpperCase()}`
}

const SECTION_THEN_COMPONENT = /(?<![A-Za-z0-9])(\d{2}[A-Z]?)\s*[-/]\s*([A-Za-z]{3,10})\b/g
const COMPONENT_THEN_SECTION = /\b([A-Za-z]{3,10})\s*[-/]?\s*(\d{2}[A-Z]?)(?![0-9:.])/g

/** A section and the kind of meeting written together: `01-LEC`, `01A DIS`, `LEC 01`. */
export function findSectionAndComponent(text: string): { section: string; component: string } | null {
  for (const m of text.matchAll(SECTION_THEN_COMPONENT)) {
    const c = component(m[2].toLowerCase())
    if (c) return { section: m[1], component: c }
  }
  for (const m of text.matchAll(COMPONENT_THEN_SECTION)) {
    const c = component(m[1].toLowerCase())
    if (c) return { section: m[2], component: c }
  }
  return null
}

/** A section named in running text: `Section 01A`, `Sec 02`, `(01B)`. */
export function findSection(text: string): string | null {
  const m = /(?:\bsec(?:tion)?\.?\s*|\()(\d{2}[A-Z]?)\b/i.exec(text)
  return m ? m[1].toUpperCase() : null
}

// ---- dates ---------------------------------------------------------------------------------------------------

const US_DATE = /(?<![0-9])([0-9OolI|]{1,2})\s*[/\\]\s*([0-9OolI|]{1,2})\s*[/\\]\s*([0-9OolI|SB]{4})(?![0-9])/g

/** Dates written `09/24/2026`, as `2026-09-24`. */
export function findDates(text: string): string[] {
  const dates: string[] = []
  for (const m of text.matchAll(US_DATE)) {
    const month = tryInt(fixDigits(m[1]))
    const day = tryInt(fixDigits(m[2]))
    const year = tryInt(fixDigits(m[3]))
    if (month === null || day === null || year === null || month < 1 || month > 12 || day < 1 || day > 31) continue
    if (year < 2000 || year > 2100) continue
    const d = new Date(Date.UTC(year, month - 1, day))
    if (d.getUTCMonth() !== month - 1) continue
    dates.push(`${String(year).padStart(4, '0')}-${String(month).padStart(2, '0')}-${String(day).padStart(2, '0')}`)
  }
  return dates
}

// ---- rooms ---------------------------------------------------------------------------------------------------

const GLYPH = /^(?:[•·●○◦▪▫■□*@>▶►|]+|[OQ0@])\s+(?=[A-Za-z0-9])/
const LABEL = /^(?:room|rm|location|loc|where|building)\s*:\s*/i
const LOST_L = /(?<=[A-Za-z])I(?=[a-z])/g
const LOST_L_IN_WORD = /\b(?:Cirm|Bidg)\b/g

/** A room as written on the page, without the pin or bullet drawn before it or a label such as `Room:`. */
export function cleanRoom(text: string): string {
  // an I between letters is an l the reader could not tell from it: `CIrm` is `Clrm`, and `Bidg` is `Bldg`
  let room = normalizeText(text.replaceAll('‖', ' '))
    .replace(LOST_L, 'l')
    .replace(LOST_L_IN_WORD, (m) => (m === 'Cirm' ? 'Clrm' : 'Bldg'))
  room = room.replace(GLYPH, '').replace(LABEL, '')
  room = room.replace(/[\s,;:|.-]+$/, '').trim()
  return room.startsWith('(') && room.endsWith(')') ? room.slice(1, -1).trim() : room
}

const ONLINE = /^(?:(?:online|remote|zoom|asynchronous|async)\b|web$)/i
const TBA = /^(?:tba|tbd|to be announced|no room)$/i

/** True for `Online` and `TBA`, which are places to be but not rooms. */
export const isNoRoom = (text: string) => ONLINE.test(text.trim()) || TBA.test(text.trim())

const PLACE_WORD = /\b(?:hall|auditorium|theat(?:er|re)|library|center|centre|commons|gym|gymnasium|annex|building|bldg)\b/i

/** True if `text` could be a room: a building and a number, a named place, `Online` or `TBA`. */
export function looksLikeRoom(text: string): boolean {
  const room = cleanRoom(text)
  if (!room || room.length > 44) return false
  if (isNoRoom(room)) return true
  if (hasClock(room) || findDates(room).length) return false
  if (!/[A-Za-z]{2}/.test(room)) return false
  return /[0-9]/.test(room) || (room.includes(' ') && PLACE_WORD.test(room))
}
