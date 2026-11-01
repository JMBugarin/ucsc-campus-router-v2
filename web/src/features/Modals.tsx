import { GlassBanner, GlassModal, GlassSegmentedControl, GlassSwitch, Divider } from '../design/components'
import { SHUTTLES, TRANSIT_LINKS } from '../data/campus'
import type { ThemeMode } from '../state/prefs'

export function TransitModal({ open, onClose }: { open: boolean; onClose: () => void }) {
  return (
    <GlassModal open={open} onClose={onClose} title="Shuttles and buses">
      <p className="note" style={{ marginTop: 0 }}>
        UCSC runs a campus circulator and is served by Santa Cruz METRO. Stops are on the map under Transit.
      </p>
      <ul className="plain">
        {SHUTTLES.map((s) => (
          <li key={s.name}>
            <strong>{s.name}</strong>
            <span>{s.note}</span>
          </li>
        ))}
      </ul>
      <GlassBanner tone="warning" title="No live times here">
        This map has no arrival data: no authorized free live feed was available. Check the official pages for routes and schedules.
      </GlassBanner>
      <div className="links">
        <a href={TRANSIT_LINKS.tapsBuses} target="_blank" rel="noopener">UCSC Buses &amp; Shuttles</a>
        <a href={TRANSIT_LINKS.metro} target="_blank" rel="noopener">Santa Cruz METRO</a>
      </div>
    </GlassModal>
  )
}

export function AboutModal({
  open,
  onClose,
  mode,
  onMode,
  reduceMotion,
  onReduceMotion,
  solid,
  onSolid,
}: {
  open: boolean
  onClose: () => void
  mode: ThemeMode
  onMode: (m: ThemeMode) => void
  reduceMotion: boolean
  onReduceMotion: (v: boolean) => void
  solid: boolean
  onSolid: (v: boolean) => void
}) {
  return (
    <GlassModal open={open} onClose={onClose} title="Settings and about">
      <div className="setrow">
        <span>Appearance</span>
        <GlassSegmentedControl
          label="Appearance"
          value={mode}
          onChange={onMode}
          options={[
            { value: 'auto', label: 'Auto' },
            { value: 'light', label: 'Light' },
            { value: 'dark', label: 'Dark' },
          ]}
        />
      </div>
      <div className="setrow">
        <span>Reduce motion</span>
        <GlassSwitch label="Reduce motion" checked={reduceMotion} onChange={onReduceMotion} />
      </div>
      <div className="setrow">
        <span>
          Opaque panels
          <small>More readable in bright sunlight</small>
        </span>
        <GlassSwitch label="Opaque panels" checked={solid} onChange={onSolid} />
      </div>
      <Divider />
      <h3>Data and credits</h3>
      <p className="note">
        Basemap: <a href="https://openfreemap.org" target="_blank" rel="noopener">OpenFreeMap</a> and{' '}
        <a href="https://openmaptiles.org" target="_blank" rel="noopener">OpenMapTiles</a>, data © <a href="https://www.openstreetmap.org/copyright" target="_blank" rel="noopener">OpenStreetMap contributors</a> (ODbL). Hillshade: Mapzen terrain tiles on AWS Open Data. Walking paths, stops, parking and landmarks come from OpenStreetMap; academic building names and nicknames come from UCSC&apos;s public classroom data.
      </p>
      <h3>Limits</h3>
      <ul className="plain note">
        <li>Routes follow mapped paths only. Indoor routing, closures and construction are not known.</li>
        <li>Stairs and bridges come from OpenStreetMap tags. Avoiding stairs is not a verified accessibility route; see the <a href="https://ada.ucsc.edu/accessibility-map/" target="_blank" rel="noopener">UCSC accessibility map</a>.</li>
        <li>Walking times are estimates from distance and 10 m elevation data.</li>
        <li>Not an official UCSC product.</li>
      </ul>
    </GlassModal>
  )
}
