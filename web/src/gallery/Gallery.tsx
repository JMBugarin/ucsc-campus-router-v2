import { useEffect, useMemo, useRef, useState, type ReactNode } from 'react'
import { MapView } from '../map/MapView'
import {
  Divider,
  GlassBanner,
  GlassButton,
  GlassIconButton,
  GlassList,
  GlassListRow,
  GlassModal,
  GlassPanel,
  GlassSearch,
  GlassSegmentedControl,
  GlassSheet,
  GlassSwitch,
  GlassToolbar,
  GlassTooltip,
  SectionLabel,
  Spinner,
  StatusPill,
} from '../design/components'
import { CATEGORY_COLOR } from '../design/tokens'
import { CategoryChips, KIND_ICON } from '../features/Browse'
import { PlaceDetail } from '../features/PlaceDetail'
import { Directions } from '../features/Directions'
import { SearchIndex } from '../data/search'
import { loadGraph, loadPlaces } from '../data/campus'
import { buildGraph, type Graph } from '../routing/graph'
import { endpointOf, planRoute, type Plan } from '../routing/plan'
import type { Place } from '../data/types'
import { useTheme } from '../state/prefs'

/** Real map locations used as backdrops: the worst cases for glass readability. */
export const BACKDROPS = {
  forest: { lng: -122.0605, lat: 36.9968, zoom: 16.2, label: 'Dark redwood forest' },
  bright: { lng: -122.0548, lat: 36.9976, zoom: 17.2, label: 'Pale plazas and roads' },
  detail: { lng: -122.0643, lat: 36.9974, zoom: 17.4, label: 'Dense paths and buildings' },
  terrain: { lng: -122.0560, lat: 37.0030, zoom: 14.2, label: 'Hillshade terrain' },
} as const
export type BackdropName = keyof typeof BACKDROPS

function Cell({ id, title, children, width = 392 }: { id: string; title: string; children: ReactNode; width?: number }) {
  return (
    <section data-gallery={id} className="gal-cell" style={{ width }} aria-label={title}>
      {children}
    </section>
  )
}

export function Gallery() {
  const q = new URLSearchParams(location.hash.split('?')[1] ?? '')
  const bd = (q.get('bd') as BackdropName) in BACKDROPS ? (q.get('bd') as BackdropName) : 'forest'
  const { theme } = useTheme()
  const [places, setPlaces] = useState<Place[]>([])
  const [graph, setGraph] = useState<Graph | null>(null)
  const [seg, setSeg] = useState<'a' | 'b' | 'c'>('b')
  const [on, setOn] = useState(true)
  const [sheet, setSheet] = useState<'half' | 'peek' | 'full'>('half')
  const ready = useRef(false)

  useEffect(() => {
    Promise.all([loadPlaces(), loadGraph()]).then(([p, g]) => {
      setPlaces(p.places)
      setGraph(buildGraph(g))
      ready.current = true
    })
  }, [])
  const byId = useMemo(() => new Map(places.map((p) => [p.id, p])), [places])
  const index = useMemo(() => new SearchIndex(places), [places])
  const plan: Plan | null = useMemo(() => {
    const a = byId.get('quarry-plaza')
    const b = byId.get('mchenry-library')
    if (!graph || !a || !b) return null
    const r = planRoute(graph, endpointOf(a), endpointOf(b))
    return 'error' in r ? null : r
  }, [graph, byId])

  const rows = ['mchenry-library', 'quarry-plaza', 'science-hill', 'kresge-college'].map((i) => byId.get(i)).filter((p): p is Place => !!p)
  const cam = BACKDROPS[bd]
  const noop = () => undefined

  useEffect(() => {
    document.body.dataset.gallery = 'ready'
  }, [])

  return (
    <div className="gal" data-ready={places.length > 0 && !!graph}>
      <MapView
        theme={theme}
        places={[]}
        selected={null}
        route={null}
        endpoints={null}
        you={null}
        padding={{ top: 0, bottom: 0, left: 0, right: 0 }}
        onSelect={noop}
        interactive={false}
        initial={{ lng: cam.lng, lat: cam.lat, zoom: cam.zoom }}
      />
      <div className="gal-grid">
        <Cell id="search" title="Search panel">
          <GlassPanel>
            <div className="searchbar">
              <GlassSearch label="Search" value="mchen" onChange={noop} force="focus" placeholder="Search" />
              <CategoryChips value="library" onChange={noop} />
            </div>
            <div className="panelbody" style={{ overflow: 'visible' }}>
              <GlassList label="Search results">
                {rows.map((p, i) => (
                  <GlassListRow key={p.id} icon={KIND_ICON[p.kind]} iconColor={CATEGORY_COLOR[p.kind]} title={p.name} subtitle={p.subtitle ?? p.kind} selected={i === 0} force={i === 2 ? 'hover' : undefined} />
                ))}
              </GlassList>
            </div>
          </GlassPanel>
        </Cell>

        <Cell id="list-states" title="List states" width={392}>
          <GlassPanel>
            <div className="panelbody" style={{ overflow: 'visible' }}>
              <SectionLabel>Rest · hover · selected · disabled</SectionLabel>
              <GlassList label="States">
                <GlassListRow icon="library" title="McHenry Library" subtitle="Rest" />
                <GlassListRow icon="library" title="McHenry Library" subtitle="Hover" force="hover" />
                <GlassListRow icon="library" title="McHenry Library" subtitle="Selected" selected />
                <GlassListRow icon="library" title="McHenry Library" subtitle="Disabled" disabled />
              </GlassList>
            </div>
          </GlassPanel>
        </Cell>

        <Cell id="buttons" title="Buttons and controls">
          <GlassPanel style={{ padding: 16, display: 'grid', gap: 14 }}>
            <div style={{ display: 'flex', gap: 8, flexWrap: 'wrap' }}>
              <GlassButton variant="primary" icon="route">Directions</GlassButton>
              <GlassButton variant="primary" force="hover">Hover</GlassButton>
              <GlassButton variant="primary" force="press">Press</GlassButton>
              <GlassButton variant="primary" force="disabled">Disabled</GlassButton>
            </div>
            <div style={{ display: 'flex', gap: 8, flexWrap: 'wrap' }}>
              <GlassButton>Secondary</GlassButton>
              <GlassButton force="hover">Hover</GlassButton>
              <GlassButton force="press">Press</GlassButton>
              <GlassButton force="disabled">Disabled</GlassButton>
              <GlassButton variant="ghost">Ghost</GlassButton>
              <GlassButton size="s" aria-pressed="true" icon="library">Libraries</GlassButton>
            </div>
            <Divider />
            <div style={{ display: 'flex', alignItems: 'center', gap: 16, flexWrap: 'wrap' }}>
              <GlassSegmentedControl label="Appearance" value={seg} onChange={setSeg} options={[{ value: 'a', label: 'Auto' }, { value: 'b', label: 'Light' }, { value: 'c', label: 'Dark' }]} />
              <GlassSwitch label="On" checked={on} onChange={setOn} />
              <GlassSwitch label="Off" checked={false} onChange={noop} />
              <GlassSwitch label="Disabled" checked={false} disabled onChange={noop} />
              <StatusPill tone="success">On campus</StatusPill>
              <StatusPill tone="warning">Stairs</StatusPill>
              <StatusPill tone="danger">Closed</StatusPill>
            </div>
          </GlassPanel>
        </Cell>

        <Cell id="toolbar" title="Toolbar and tooltip" width={200}>
          <div style={{ display: 'flex', gap: 14, alignItems: 'flex-start', padding: '0 0 0 110px' }}>
            <GlassToolbar label="Map controls">
              <GlassTooltip text="Zoom in" force="show"><GlassIconButton icon="plus" label="Zoom in" /></GlassTooltip>
              <GlassIconButton icon="minus" label="Zoom out" force="hover" />
              <GlassIconButton icon="locate" label="My location" />
              <GlassIconButton icon="info" label="About" force="disabled" />
            </GlassToolbar>
          </div>
        </Cell>

        <Cell id="banners" title="Banners">
          <GlassPanel style={{ padding: 12, display: 'grid', gap: 8 }}>
            <GlassBanner title="Schedules and live arrivals">No arrival data is shown here.</GlassBanner>
            <GlassBanner tone="success" title="Link copied" />
            <GlassBanner tone="warning" title="Stairs on this route">No step-free path is mapped between these places.</GlassBanner>
            <GlassBanner tone="danger" title="Campus data failed to load">Check your connection and reload.</GlassBanner>
          </GlassPanel>
        </Cell>

        <Cell id="states" title="Loading, empty and error states">
          <GlassPanel style={{ padding: 12, display: 'grid', gap: 10 }}>
            <div style={{ display: 'flex', alignItems: 'center', gap: 10, padding: 10 }}>
              <Spinner /> Loading campus data
            </div>
            <Divider />
            <GlassBanner tone="warning" title="No matches">Try a building name, a nickname like BE or S&amp;E, or pick a category.</GlassBanner>
            <GlassBanner tone="danger" title="Location unavailable">Location permission was denied.</GlassBanner>
          </GlassPanel>
        </Cell>

        <Cell id="place" title="Place details">
          {byId.get('mchenry-library') && (
            <GlassPanel style={{ padding: 12 }}>
              <PlaceDetail place={byId.get('mchenry-library')!} nearGraph onBack={noop} onDirections={noop} onShare={noop} onTransit={noop} />
            </GlassPanel>
          )}
        </Cell>

        <Cell id="directions" title="Directions">
          {graph && plan && (
            <GlassPanel style={{ padding: 12 }}>
              <Directions from={{ id: 'quarry-plaza', name: 'Quarry Plaza' }} to={{ id: 'mchenry-library', name: 'McHenry Library' }} plan={plan} error={null} avoidStairs={false} onAvoidStairs={noop} onPickFrom={noop} onPickTo={noop} onSwap={noop} onClose={noop} index={index} hasLocation={false} onLocate={noop} locating={false} locationError={null} straightMeters={null} />
            </GlassPanel>
          )}
        </Cell>

        <Cell id="sheet" title="Bottom sheet" width={390}>
          <div style={{ height: 360, position: 'relative' }}>
            <GlassSheet inline detent={sheet} onDetent={setSheet} label="Sheet">
              <div className="searchbar">
                <GlassSearch label="Search" value="" onChange={noop} placeholder="Search buildings, dining, parking…" />
              </div>
              <GlassList label="Sheet results">
                {rows.slice(0, 3).map((p) => (
                  <GlassListRow key={p.id} icon={KIND_ICON[p.kind]} iconColor={CATEGORY_COLOR[p.kind]} title={p.name} subtitle={p.kind} />
                ))}
              </GlassList>
            </GlassSheet>
          </div>
        </Cell>

        <Cell id="modal" title="Modal">
          <GlassModal inline open onClose={noop} title="Shuttles and buses">
            <p className="note" style={{ marginTop: 0 }}>Stops are on the map under Transit.</p>
            <GlassBanner tone="warning" title="No live times here">Check the official pages for schedules.</GlassBanner>
          </GlassModal>
        </Cell>
      </div>
    </div>
  )
}
