import { GlassBanner, GlassButton, GlassList, GlassListRow, SectionLabel } from '../design/components'
import { CATEGORY_COLOR, CATEGORY_LABEL, type Category } from '../design/tokens'
import type { Place } from '../data/types'
import type { IconName } from '../design/icons'
import { floorText } from '../data/rooms'

export const KIND_ICON: Record<Category, IconName> = {
  academic: 'academic',
  college: 'college',
  library: 'library',
  dining: 'dining',
  landmark: 'landmark',
  transit: 'transit',
  parking: 'parking',
  room: 'door',
}
const KIND_NAME: Record<Category, string> = { academic: 'Academic building', college: 'College', library: 'Library', dining: 'Dining', landmark: 'Landmark', transit: 'Transit stop', parking: 'Parking', room: 'Classroom' }
export const kindName = (p: Place) => {
  if (p.kind === 'room') return [KIND_NAME.room, floorText(p.room)].filter(Boolean).join(' · ')
  return p.subtitle && p.kind !== 'academic' ? `${KIND_NAME[p.kind]} · ${p.subtitle}` : KIND_NAME[p.kind]
}
const CHIPS = (Object.keys(CATEGORY_LABEL) as Category[]).filter((c) => c !== 'room')

export function CategoryChips({ value, onChange }: { value: Category | null; onChange: (c: Category | null) => void }) {
  return (
    <div className="chips" role="group" aria-label="Categories">
      {CHIPS.map((c) => (
        <GlassButton key={c} size="s" icon={KIND_ICON[c]} aria-pressed={value === c} onClick={() => onChange(value === c ? null : c)}>
          {CATEGORY_LABEL[c]}
        </GlassButton>
      ))}
    </div>
  )
}

export function PlaceRows({
  places,
  activeId,
  onPick,
  listId,
  label,
  empty,
}: {
  places: Place[]
  activeId?: string
  onPick: (p: Place) => void
  listId?: string
  label: string
  empty?: string
}) {
  if (!places.length) return <GlassBanner tone="warning" title="No matches">{empty ?? 'Try a room like BE 152, a building name, a nickname like S&E, or pick a category.'}</GlassBanner>
  return (
    <GlassList id={listId} label={label}>
      {places.map((p) => (
        <GlassListRow key={p.id} id={`opt-${p.id}`} icon={KIND_ICON[p.kind]} iconColor={CATEGORY_COLOR[p.kind]} title={p.name} subtitle={kindName(p)} selected={p.id === activeId} onClick={() => onPick(p)} />
      ))}
    </GlassList>
  )
}

export function Featured({ places, recent = [], onPick, onTransit }: { places: Place[]; recent?: Place[]; onPick: (p: Place) => void; onTransit: () => void }) {
  return (
    <div>
      {recent.length > 0 && (
        <>
          <SectionLabel>Recent</SectionLabel>
          <PlaceRows places={recent} onPick={onPick} label="Recent places" />
        </>
      )}
      <SectionLabel>Popular</SectionLabel>
      <PlaceRows places={places} onPick={onPick} label="Popular places" />
      <SectionLabel>Getting around</SectionLabel>
      <GlassList label="Transportation">
        <GlassListRow icon="transit" iconColor={CATEGORY_COLOR.transit} title="Shuttles and buses" subtitle="Campus circulator and METRO" onClick={onTransit} />
      </GlassList>
    </div>
  )
}
