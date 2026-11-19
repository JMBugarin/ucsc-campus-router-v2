import { useState } from 'react'
import { GlassBanner, GlassButton, GlassSegmentedControl, SectionLabel } from '../../design/components'
import type { Meeting } from '../../schedule/meeting'
import { meetingLabel, timeLabel } from '../../schedule/meeting'
import { WEEKDAY_NAMES, dayLabel, pacificDate } from '../../schedule/time'
import { notificationsSupported } from '../../schedule/notify'

export function Schedule({
  meetings,
  persistent,
  reminderLead,
  onPaste,
  onAdd,
  onEdit,
  onReminders,
  onClear,
  now,
}: {
  meetings: Meeting[]
  persistent: boolean
  reminderLead: number | null
  onPaste: () => void
  onAdd: () => void
  onEdit: (index: number) => void
  onReminders: (lead: number | null) => void
  onClear: () => void
  now: number
}) {
  const [confirm, setConfirm] = useState(false)
  const days = WEEKDAY_NAMES.map((name, d) => ({
    name,
    list: meetings
      .map((m, i) => ({ m, i }))
      .filter(({ m }) => m.days.includes(d))
      .sort((a, b) => a.m.start.localeCompare(b.m.start)),
  })).filter((x) => x.list.length)
  const oneOffs = meetings.map((m, i) => ({ m, i })).filter(({ m }) => !m.days.length)
  const today = pacificDate(now)
  return (
    <section className="schedule" aria-label="Schedule">
      <h1 className="detail__title">Schedule</h1>
      <div className="schedule__add">
        <GlassButton variant="primary" icon="layers" onClick={onPaste}>
          Paste from MyUCSC
        </GlassButton>
        <GlassButton icon="plus" onClick={onAdd}>
          Add a class
        </GlassButton>
      </div>
      {!persistent && (
        <GlassBanner tone="warning" title="This browser won't keep your schedule">
          Private browsing or blocked site data means your classes disappear when you close this page.
        </GlassBanner>
      )}
      {!meetings.length && <p className="note">No classes yet. Paste the Class Schedule page from MyUCSC, or add each class by hand.</p>}
      {days.map(({ name, list }) => (
        <div key={name}>
          <SectionLabel>{name}</SectionLabel>
          <ul className="week">
            {list.map(({ m, i }) => (
              <li key={`${name}-${i}`}>
                <button className="week__row" onClick={() => onEdit(i)} aria-label={`Edit ${meetingLabel(m)} on ${name}`}>
                  <span className="week__time tabular">{timeLabel(m)}</span>
                  <span className="week__main">
                    <strong>{meetingLabel(m)}</strong>
                    <small>{m.location || 'No room'}</small>
                    {(m.skip_dates ?? []).some((s) => s >= today) && <small>Skipping {(m.skip_dates ?? []).filter((s) => s >= today).map(dayLabel).join(', ')}</small>}
                  </span>
                </button>
              </li>
            ))}
          </ul>
        </div>
      ))}
      {oneOffs.length > 0 && (
        <div>
          <SectionLabel>One-off</SectionLabel>
          <ul className="week">
            {oneOffs.map(({ m, i }) => (
              <li key={`once-${i}`}>
                <button className="week__row" onClick={() => onEdit(i)}>
                  <span className="week__time tabular">{dayLabel(m.start_date)}</span>
                  <span className="week__main">
                    <strong>{meetingLabel(m)}</strong>
                    <small>{timeLabel(m)} · {m.location || 'No room'}</small>
                  </span>
                </button>
              </li>
            ))}
          </ul>
        </div>
      )}
      {meetings.length > 0 && (
        <>
          <SectionLabel>Class reminders</SectionLabel>
          <GlassSegmentedControl<string>
            label="Remind me before class"
            value={reminderLead === null ? 'off' : String(reminderLead)}
            onChange={(v) => onReminders(v === 'off' ? null : Number(v))}
            options={[
              { value: 'off', label: 'Off' },
              { value: '5', label: '5 min' },
              { value: '10', label: '10 min' },
              { value: '15', label: '15 min' },
            ]}
          />
          <p className="note">
            {notificationsSupported()
              ? 'Reminders show while Classmap is open in a tab. On an iPhone, add Classmap to your Home Screen first.'
              : "This browser can't show notifications; reminders appear on this page instead."}
          </p>
          <SectionLabel>Your data</SectionLabel>
          <p className="note">Your schedule is saved only in this browser. It is never uploaded.</p>
          <GlassButton size="s" icon="close" onClick={() => (confirm ? (onClear(), setConfirm(false)) : setConfirm(true))}>
            {confirm ? 'Tap again to remove every class' : 'Remove all classes'}
          </GlassButton>
        </>
      )}
    </section>
  )
}
