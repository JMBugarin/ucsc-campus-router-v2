import { useEffect } from 'react'
import { planReminders } from './reminders'
import { schedule } from './store'
import type { Meeting } from './meeting'

export const notificationsSupported = () => typeof window !== 'undefined' && 'Notification' in window

export async function askToNotify(): Promise<NotificationPermission | 'unsupported'> {
  if (!notificationsSupported()) return 'unsupported'
  if (Notification.permission !== 'default') return Notification.permission
  try {
    return await Notification.requestPermission()
  } catch {
    return 'denied'
  }
}

async function show(title: string, body: string) {
  try {
    const reg = await navigator.serviceWorker?.getRegistration()
    if (reg) return void (await reg.showNotification(title, { body, tag: title, icon: `${import.meta.env.BASE_URL}icon-192.png` }))
  } catch {
    /* fall through to a page notification */
  }
  try {
    new Notification(title, { body })
  } catch {
    /* some browsers only notify from a service worker */
  }
}

/** Fires class reminders while Classmap is open, one timer at a time. */
export function useClassReminders(meetings: Meeting[], holidays: Set<string> | null, lead: number | null, onShown: (text: string) => void) {
  useEffect(() => {
    if (lead === null || !holidays || !meetings.length) return
    let timer: number | undefined
    const arm = () => {
      const next = planReminders(meetings, Date.now(), holidays, lead, new Set(schedule.reminders.sent))[0]
      if (!next) return
      timer = window.setTimeout(() => {
        schedule.markSent(next.key)
        if (notificationsSupported() && Notification.permission === 'granted') void show(next.title, next.body)
        onShown(`${next.title}. ${next.body}`)
        arm()
      }, Math.max(0, next.at - Date.now()))
    }
    arm()
    return () => window.clearTimeout(timer)
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [meetings, holidays, lead])
}
