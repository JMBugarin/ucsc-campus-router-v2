import { GlassBanner, GlassButton, GlassIconButton, StatusPill } from '../design/components'
import { CATEGORY_LABEL } from '../design/tokens'
import type { Place } from '../data/types'
import { TRANSIT_LINKS } from '../data/campus'
import { kindName } from './Browse'

export function PlaceDetail({ place, onBack, onDirections, onShare, onTransit, nearGraph }: { place: Place; onBack: () => void; onDirections: () => void; onShare: () => void; onTransit: () => void; nearGraph: boolean }) {
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
      <dl className="facts">
        {place.aliases.length > 0 && (
          <>
            <dt>Also known as</dt>
            <dd>{place.aliases.slice(0, 6).join(', ')}</dd>
          </>
        )}
        {place.rooms ? (
          <>
            <dt>Classrooms</dt>
            <dd>{place.rooms} with known locations</dd>
          </>
        ) : null}
        <dt>Coordinates</dt>
        <dd className="tabular">
          {place.lat.toFixed(5)}, {place.lon.toFixed(5)}
        </dd>
        <dt>Source</dt>
        <dd>{place.source === 'osm' ? 'OpenStreetMap' : 'UCSC classroom data + OpenStreetMap'}</dd>
      </dl>
      {place.kind === 'transit' && (
        <GlassBanner title="Schedules and live arrivals">
          This map does not show arrival times. Use the{' '}
          <a href={TRANSIT_LINKS.metro} target="_blank" rel="noopener">
            METRO
          </a>{' '}
          or{' '}
          <button className="linkbtn" onClick={onTransit}>
            campus shuttle
          </button>{' '}
          information.
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
