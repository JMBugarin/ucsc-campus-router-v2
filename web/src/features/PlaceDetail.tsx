import { GlassBanner, GlassButton, GlassIconButton, SectionLabel, StatusPill } from '../design/components'
import { CATEGORY_LABEL } from '../design/tokens'
import { Icon } from '../design/icons'
import type { Place } from '../data/types'
import { ACCESS_LABEL, checkedText, doorSentence, doorTitle, floorText, roomGroups, type RoomGroup } from '../data/rooms'
import { AuditPanel } from './AuditPanel'
import { RoomFeedback } from './Feedback'
import { TRANSIT_LINKS } from '../data/campus'
import { kindName } from './Browse'
import { Departures } from './Departures'
import type { TransitData, Clock } from '../transit/schedule'
import type { LiveState } from '../transit/useTransit'

interface DetailProps {
  transit?: TransitData | null
  now?: Clock
  live?: LiveState
  place: Place
  byId: Map<string, Place>
  onOpen: (p: Place) => void
  onBack: () => void
  onDirections: () => void
  onShare: () => void
  onTransit: () => void
  nearGraph: boolean
  auditMode?: boolean
  onLocate?: () => Promise<[number, number] | null>
}

export function RoomList({ groups, current, onOpen }: { groups: RoomGroup[]; current?: string; onOpen: (p: Place) => void }) {
  return (
    <div className="roomgroups">
      {groups.map((g) => (
        <div key={g.key} className="roomgroup">
          <div className="roomgroup__title">{g.title}</div>
          <div className="roomgroup__rooms">
            {g.rooms.map((r) => (
              <button key={r.id} className="roomchip" aria-current={r.id === current ? 'true' : undefined} aria-label={r.name} onClick={() => onOpen(r)}>
                {r.room?.number}
              </button>
            ))}
          </div>
        </div>
      ))}
    </div>
  )
}

function RoomDetail({ place, byId, onOpen, onBack, onDirections, onShare, nearGraph, auditMode, onLocate }: DetailProps) {
  const info = place.room!
  const g = info.guide
  const building = byId.get(info.building)
  const groups = building ? roomGroups(building, byId) : []
  const sentence = doorSentence(info)
  const sub = [building?.name ?? place.subtitle, floorText(info), g?.wing].filter(Boolean).join(' · ')
  return (
    <article aria-label={place.name} className="detail">
      <div className="detail__head">
        <GlassIconButton icon="back" label="Back to search" onClick={onBack} />
        <div style={{ minWidth: 0, flex: 1 }}>
          <h1 className="detail__title">{place.name}</h1>
          <div className="detail__sub">{sub}</div>
        </div>
        <GlassIconButton icon="share" label="Copy link to this room" onClick={onShare} />
      </div>
      <div className="detail__badges">
        {g?.access ? <StatusPill tone="success">{ACCESS_LABEL[g.access].title}</StatusPill> : <StatusPill tone="warning">Not checked on foot yet</StatusPill>}
        {g?.stepFree === true && <StatusPill tone="accent">Step-free from the door</StatusPill>}
      </div>
      <GlassButton variant="primary" icon="route" onClick={onDirections} disabled={!nearGraph || !info.door}>
        Directions to the door
      </GlassButton>
      <section className="arrive" aria-label="Getting to the room">
        <h2 className="arrive__title">
          <Icon name="door" size={16} />
          {doorTitle(info) ?? 'No mapped door'}
          {info.door?.checked && <span className="arrive__ok">checked</span>}
        </h2>
        {g?.access && <p className="arrive__line">{ACCESS_LABEL[g.access].detail}</p>}
        {g?.note && <p className="arrive__note">{g.note}</p>}
        {g?.steps && (
          <ol className="arrive__steps">
            {g.steps.map((s, i) => (
              <li key={i}>{s}</li>
            ))}
          </ol>
        )}
        {sentence && <p className="arrive__line">{sentence}</p>}
        {g?.stepFree === false && <p className="arrive__line">There are stairs between this door and the room.</p>}
        {g?.elevator && <p className="arrive__line">Elevator: {g.elevator}</p>}
        <p className="note">
          {g ? checkedText(info) : 'The room position is from UCSC’s campus map and the doors are from OpenStreetMap. Nobody has walked this one for the app yet.'}
          {g?.url && (
            <>
              {' '}
              <a href={g.url} target="_blank" rel="noopener">
                Source
              </a>
            </>
          )}
        </p>
      </section>
      <RoomFeedback place={place.id} />
      {auditMode && <AuditPanel room={place} onLocate={onLocate ?? (async () => null)} />}
      <details className="more">
        <summary>More details</summary>
        {building && groups.length > 0 && (
          <>
            <SectionLabel>Rooms in {building.name}</SectionLabel>
            <RoomList groups={groups} current={place.id} onOpen={onOpen} />
            <button className="linkbtn" onClick={() => onOpen(building)}>
              Open {building.name}
            </button>
          </>
        )}
        <dl className="facts">
          <dt>Also searched as</dt>
          <dd>{place.aliases.slice(0, 4).join(', ')}</dd>
          <dt>Room position</dt>
          <dd className="tabular">
            {place.lat.toFixed(5)}, {place.lon.toFixed(5)}
          </dd>
          <dt>Floor source</dt>
          <dd>
            {info.floor?.basis === 'checked' ? (
              'Checked on foot'
            ) : info.floor?.source ? (
              <a href={info.floor.source.url} target="_blank" rel="noopener">
                {info.floor.source.name}
              </a>
            ) : (
              'Not confirmed yet, so no floor is shown. Check the signs.'
            )}
          </dd>
        </dl>
      </details>
    </article>
  )
}

export function PlaceDetail(props: DetailProps) {
  const { place, byId, onOpen, onBack, onDirections, onShare, onTransit, nearGraph, transit, now, live } = props
  if (place.kind === 'room' && place.room) return <RoomDetail {...props} />
  const groups = roomGroups(place, byId)
  return (
    <article aria-label={place.name} className="detail">
      <div className="detail__head">
        <GlassIconButton icon="back" label="Back to search" onClick={onBack} />
        <div style={{ minWidth: 0, flex: 1 }}>
          <h1 className="detail__title">{place.name}</h1>
          <div className="detail__sub">{kindName(place)}</div>
        </div>
        <GlassIconButton icon="share" label="Copy link to this place" onClick={onShare} />
      </div>
      <div className="detail__actions">
        <GlassButton variant="primary" icon="route" onClick={onDirections} disabled={!nearGraph}>
          Directions
        </GlassButton>
        <StatusPill tone="accent">{CATEGORY_LABEL[place.kind]}</StatusPill>
      </div>
      {!nearGraph && (
        <GlassBanner tone="warning" title="No walking paths mapped here">
          This place is outside the campus path network, so walking directions are not available.
        </GlassBanner>
      )}
      {groups.length > 0 && (
        <section aria-label="Classrooms">
          <SectionLabel>Classrooms</SectionLabel>
          <RoomList groups={groups} onOpen={onOpen} />
        </section>
      )}
      <dl className="facts">
        {place.aliases.length > 0 && (
          <>
            <dt>Also known as</dt>
            <dd>{place.aliases.slice(0, 6).join(', ')}</dd>
          </>
        )}
        <dt>Coordinates</dt>
        <dd className="tabular">
          {place.lat.toFixed(5)}, {place.lon.toFixed(5)}
        </dd>
        <dt>Source</dt>
        <dd>{place.source === 'osm' ? 'OpenStreetMap' : place.source === 'metro-gtfs' ? 'Santa Cruz METRO GTFS' : place.source === 'ucsc-facilities' ? 'UCSC campus map' : 'UCSC classroom data + OpenStreetMap'}</dd>
      </dl>
      {place.stops && transit && now && live && <Departures data={transit} stopIds={place.stops} now={now} live={live} />}
      {place.kind === 'transit' && !place.stops && (
        <GlassBanner title="Schedules and live arrivals">
          Live positions for campus shuttles are only in UCSC's flexigo app. See the{' '}
          <button className="linkbtn" onClick={onTransit}>
            shuttle information
          </button>
          , or{' '}
          <a href={TRANSIT_LINKS.metro} target="_blank" rel="noopener">
            METRO
          </a>{' '}
          for buses.
        </GlassBanner>
      )}
      {place.kind === 'parking' && (
        <GlassBanner tone="warning" title="Check permit rules">
          Whether you can park here depends on your permit and the time of day. See{' '}
          <a href="https://transportation.ucsc.edu/" target="_blank" rel="noopener">
            Transportation &amp; Parking Services
          </a>
          .
        </GlassBanner>
      )}
    </article>
  )
}
