import { describe, expect, it } from 'vitest'
import { readFileSync, readdirSync } from 'node:fs'
import { parseSchedule } from '../src/schedule/ocr/parser'
import { readingFromJson } from '../src/schedule/ocr/recognized'
import { needsReview } from '../src/schedule/ocr/rows'
import { findDays, findTimeRange, findCourse, cleanRoom, sectionOfCell } from '../src/schedule/ocr/fields'

const DIR = '../app/test/fixtures/ocr'
const fixtures = readdirSync(DIR)
  .filter((f) => f.endsWith('.json'))
  .sort()
  .map((f) => ({ name: f.replace('.json', ''), ...(JSON.parse(readFileSync(`${DIR}/${f}`, 'utf8')) as { about: string; reading: unknown; expected: { problem: string | null; notes: string[]; rows: Record<string, unknown>[] } }) }))

describe('readings the phone really returned, read the way the app reads them', () => {
  it('has the recorded fixtures', () => expect(fixtures.length).toBeGreaterThanOrEqual(20))
  for (const f of fixtures) {
    it(`${f.name}: ${f.about}`, () => {
      const result = parseSchedule(readingFromJson(f.reading))
      expect(result.problem).toBe(f.expected.problem)
      expect(result.notes).toEqual(f.expected.notes)
      expect(result.rows).toHaveLength(f.expected.rows.length)
      result.rows.forEach((got, i) => {
        const w = f.expected.rows[i]
        const pick = { course: got.course, title: got.title, section: got.section, component: got.component, days: got.days, start: got.start, end: got.end, location: got.location, startDate: got.startDate, endDate: got.endDate }
        expect(pick, `row ${i}`).toEqual(Object.fromEntries(Object.keys(pick).map((k) => [k, w[k]])))
        expect([...got.issues].sort(), `issues of row ${i}`).toEqual(w.issues)
        expect(needsReview(got), `review of row ${i}`).toBe(w.needsReview)
        expect(got.confidence).toBeGreaterThanOrEqual(0)
        expect(got.confidence).toBeLessThanOrEqual(1)
      })
    })
  }
})

describe('field readers', () => {
  it('read times, days, courses, rooms and sections as the app does', () => {
    expect(findTimeRange('MWF 1:20-2:25 PM')).toMatchObject({ start: '13:20', end: '14:25' })
    expect(findTimeRange('8:00AM - 9:05AM')).toMatchObject({ start: '08:00', end: '09:05', certainty: 'exact' })
    expect(findTimeRange('1:20 - 2:25')).toMatchObject({ start: '13:20', end: '14:25', certainty: 'guessed' })
    expect(findDays('TuTh')?.days).toEqual([1, 3])
    expect(findDays('Mon, Wea, Fri')?.days).toEqual([0, 2, 4])
    expect(findCourse('CSE 2O')?.code).toBe('CSE 20')
    expect(cleanRoom('• Room: J Baskin Engr 152,')).toBe('J Baskin Engr 152')
    expect(sectionOfCell('O1A')).toBe('01A')
  })
})
