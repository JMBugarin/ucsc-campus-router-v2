import { describe, expect, it } from 'vitest'
import { readFileSync } from 'node:fs'
import { Campus, type CampusFile } from '../src/schedule/campus'
import { cleanMeeting, ScheduleError, skipping, meetingOn, type Meeting } from '../src/schedule/meeting'
import { parsePasted } from '../src/schedule/paste'
import { departure, planDay, transitions, type Walk } from '../src/schedule/dayPlan'
import { planReminders } from '../src/schedule/reminders'
import { holidaysOf, termFor, termsFromJson } from '../src/schedule/terms'
import { isoWithOffset, pacificDate, pacificInstant } from '../src/schedule/time'
import { draftFromMeeting, newDraft, problem, toMeeting } from '../src/schedule/draft'
import { ScheduleStore } from '../src/schedule/store'

const read = (f: string) => JSON.parse(readFileSync(f, 'utf8'))
const golden = read('../app/test/fixtures/golden_port.json')
const cases = read('../app/test/fixtures/schedule_cases.json')
const campus = new Campus(read('public/data/campus.json') as CampusFile)
const ms = (iso: string) => Date.parse(iso)

describe('parity with the phone app', () => {
  it('cleans meetings the same way', () => {
    for (const c of golden.clean) {
      if (c.out.error) expect(() => cleanMeeting(c.input), JSON.stringify(c.input)).toThrow(c.out.error)
      else expect(cleanMeeting(c.input)).toEqual(c.out.meeting)
    }
  })
  it('splits locations from instructors the same way', () => {
    for (const c of golden.split) expect(campus.splitLocation(c.input), c.input).toEqual(c.out)
  })
  it('resolves every location the same way', () => {
    for (const c of golden.resolve) {
      const r = campus.resolve(c.input)
      expect(r.kind, c.input).toBe(c.out.kind)
      expect(r.buildingId ?? null, c.input).toBe(c.out.building_id)
      expect(r.room ?? null, c.input).toBe(c.out.room)
      expect(r.roomKnown ?? null, c.input).toBe(c.out.room_known)
      expect(r.level ?? null, c.input).toBe(c.out.floor)
    }
  })
  it('reads pasted MyUCSC schedules the same way', () => {
    for (const c of golden.paste) {
      const got = parsePasted(c.input, campus)
      expect(got.meetings, c.input.slice(0, 40)).toEqual(c.out.meetings)
      expect(got.notes, c.input.slice(0, 40)).toEqual(c.out.notes)
    }
  })
  it('plans each shared day case the same way', () => {
    const holidays = new Set<string>(cases.holidays)
    const walks = cases.walks as Record<string, number>
    const walk: Walk = (from, to) => walks[`${from ?? '*'}>${to}`] ?? null
    expect(cases.cases.length).toBeGreaterThanOrEqual(15)
    for (const c of cases.cases) {
      const want = c.expect
      const now = ms(c.now)
      const meetings = (c.meetings as string[]).map((n) => cases.meetings[n] as Meeting)
      const plan = planDay(meetings, now, holidays)
      expect(plan.state, c.name).toBe(want.state)
      expect(plan.reason, c.name).toBe(want.reason)
      expect(plan.current ? isoWithOffset(plan.current.start) : null, c.name).toBe(want.current_start)
      expect(plan.next ? isoWithOffset(plan.next.start) : null, c.name).toBe(want.next_start)
      expect(plan.classes.map((o) => isoWithOffset(o.start)), c.name).toEqual(want.today_starts)
      if (plan.next) {
        expect(pacificDate(plan.next.start) === pacificDate(now), c.name).toBe(want.next_is_today)
        expect((plan.next.start - now) / 60000, c.name).toBeCloseTo(want.starts_in_min, 1)
      }
      const dep = departure(plan, now, walk, !!c.here)
      expect(dep?.walkMin ?? null, c.name).toBe(want.walk_minutes ?? null)
      expect(dep?.from ?? null, c.name).toBe(want.walk_from ?? null)
      expect(dep?.status ?? 'unknown', c.name).toBe(want.status)
      if (dep) {
        expect(dep.freeMin, c.name).toBeCloseTo(want.free_min, 5)
        expect(isoWithOffset(dep.leaveBy), c.name).toBe(want.leave_by)
      }
      const t = transitions(plan, walk).filter((x) => x !== null)
      expect(t.map((x) => ({ walk_min: x!.walkMin, free_min: x!.freeMin, status: x!.status })), c.name).toEqual(want.transitions)
    }
  })
  it('also accepts the nicknames students type, outside the strict app rules', () => {
    expect(campus.resolve('BE 152').kind).toBe('unknown')
    expect(campus.resolve('BE 152', true)).toMatchObject({ kind: 'building', buildingId: 'baskin-engineering', room: '152', roomKnown: true })
    expect(campus.resolve('S&E Library 206', true)).toMatchObject({ buildingId: 'science-engineering-library', room: '206' })
    expect(campus.resolve('J Baskin Engr 152', true).buildingId).toBe('baskin-engineering')
  })
  it('finds the term for a date', () => {
    const terms = termsFromJson(golden.term[0] ?? golden.term)
    expect(termFor(terms, '2026-10-01')?.name).toBe('Fall 2026')
    expect(termFor(terms, '2026-12-20')?.name).toBe('Winter 2027')
    expect(holidaysOf(terms).has('2026-11-26')).toBe(true)
  })
})

describe('pacific time', () => {
  it('turns wall clock times into instants across clock changes', () => {
    expect(isoWithOffset(pacificInstant('2026-10-12', '14:40'))).toBe('2026-10-12T14:40:00-07:00')
    expect(isoWithOffset(pacificInstant('2026-11-02', '08:00'))).toBe('2026-11-02T08:00:00-08:00')
    expect(isoWithOffset(pacificInstant('2027-03-15', '08:00'))).toBe('2027-03-15T08:00:00-07:00')
  })
})

describe('skipping a meeting', () => {
  const m = cleanMeeting({ course: 'CSE 130', days: [0, 2], start: '09:00', end: '10:00', start_date: '2026-09-24', end_date: '2026-12-04' })
  it('adds and removes a date, dropping past ones', () => {
    const s = skipping({ ...m, skip_dates: ['2026-10-01'] }, '2026-10-14', '2026-10-10')!
    expect(s.skip_dates).toEqual(['2026-10-14'])
    expect(meetingOn(s, '2026-10-14').skip_dates).toBeUndefined()
    expect(planDay([s], ms('2026-10-14T08:00:00-07:00'), new Set()).classes).toEqual([])
  })
})

describe('class drafts', () => {
  it('say what is missing and save a tidy meeting', () => {
    expect(problem(newDraft())).toMatch(/course/)
    const d = newDraft({ course: ' CSE  130 ', days: [2, 0], start: '09:00', end: '10:05', startDate: '2026-09-24', endDate: '2026-12-04', location: 'J Baskin Engr 152' })
    expect(problem(d)).toBeNull()
    expect(toMeeting(d)).toMatchObject({ course: 'CSE 130', days: [0, 2] })
    expect(problem({ ...d, end: '08:00' })).toMatch(/after the start/)
    const back = draftFromMeeting(toMeeting(d))
    expect(toMeeting(back)).toEqual(toMeeting(d))
  })
})

describe('reminders', () => {
  it('plan one reminder before each class this week', () => {
    const m = cleanMeeting({ course: 'CSE 130', component: 'Lecture', days: [0, 2], start: '09:00', end: '10:00', location: 'J Baskin Engr 152', start_date: '2026-09-24', end_date: '2026-12-04' })
    const now = ms('2026-10-12T08:00:00-07:00')
    const plan = planReminders([m], now, new Set(), 10)
    expect(plan[0]).toMatchObject({ title: 'CSE 130 Lecture in 10 min', body: 'J Baskin Engr 152 at 9:00 AM.' })
    expect(isoWithOffset(plan[0].at)).toBe('2026-10-12T08:50:00-07:00')
    expect(plan.map((r) => isoWithOffset(r.at))).toEqual(['2026-10-12T08:50:00-07:00', '2026-10-14T08:50:00-07:00'])
    expect(planReminders([m], now, new Set(), 10, new Set([plan[0].key]))).toHaveLength(1)
    expect(planReminders([m], ms('2026-10-12T08:55:00-07:00'), new Set(), 10)[0].key).toBe(plan[1].key)
  })
})

describe('the saved schedule', () => {
  const memory = () => {
    const m = new Map<string, string>()
    return { getItem: (k: string) => m.get(k) ?? null, setItem: (k: string, v: string) => void m.set(k, v), removeItem: (k: string) => void m.delete(k) } as unknown as Storage
  }
  it('keeps classes in this browser and ignores repeats', () => {
    const storage = memory()
    const s = new ScheduleStore(() => storage)
    const m = cleanMeeting({ course: 'CSE 130', days: [0], start: '09:00', end: '10:00', start_date: '2026-09-24', end_date: '2026-12-04' })
    expect(s.add([m, m])).toBe(1)
    expect(s.add([m])).toBe(0)
    expect(new ScheduleStore(() => storage).all).toEqual([m])
  })
  it('throws away a corrupted save instead of breaking', () => {
    const storage = memory()
    storage.setItem('classmap.schedule.v1', '{"meetings":[{"course":""}]}')
    expect(new ScheduleStore(() => storage).all).toEqual([])
  })
  it('works without storage', () => {
    const s = new ScheduleStore(() => {
      throw new Error('blocked')
    })
    const m = cleanMeeting({ course: 'CSE 130', days: [0], start: '09:00', end: '10:00', start_date: '2026-09-24', end_date: '2026-12-04' })
    expect(s.add([m])).toBe(1)
    expect(s.persistent).toBe(false)
  })
  it('rejects nonsense with a readable message', () => {
    expect(() => cleanMeeting({ course: 'X', days: [9] })).toThrow(ScheduleError)
  })
})
