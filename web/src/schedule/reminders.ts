import { occurrences } from './dayPlan'
import { meetingLabel, type Meeting } from './meeting'
import { addDays, clockAt, isoWithOffset, pacificDate } from './time'

export const PLAN_AHEAD_DAYS = 7

export interface Reminder {
  key: string
  at: number
  title: string
  body: string
}

/** A reminder `lead` minutes before each class over the next week. Keys in `sent` and times already passed are left out. */
export function planReminders(meetings: Meeting[], now: number, holidays: Set<string>, lead: number, sent: Set<string> = new Set(), days = PLAN_AHEAD_DAYS): Reminder[] {
  const today = pacificDate(now)
  const plan: Reminder[] = []
  for (let offset = 0; offset < days; offset++) {
    for (const c of occurrences(meetings, addDays(today, offset), holidays)) {
      if (c.start <= now) continue
      const key = `${isoWithOffset(c.start)}|class`
      const at = c.start - lead * 60000
      if (at < now || sent.has(key)) continue
      const when = clockAt(c.start)
      plan.push({
        key,
        at,
        title: lead > 0 ? `${meetingLabel(c.meeting)} in ${lead} min` : `${meetingLabel(c.meeting)} is starting`,
        body: c.meeting.location ? `${c.meeting.location} at ${when}.` : `Starts at ${when}.`,
      })
    }
  }
  return plan.sort((a, b) => a.at - b.at)
}
