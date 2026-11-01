import { useCallback, useEffect, useMemo, useRef, useState } from 'react'
import { MapView, type MapHandle } from './map/MapView'
import { GlassBanner, GlassIconButton, GlassPanel, GlassSearch, GlassSheet, GlassToolbar, GlassTooltip, Spinner, type Detent } from './design/components'
import { useMedia } from './design/motion'
import { MOBILE_QUERY } from './design/tokens'
import type { Category } from './design/tokens'
import { loadGraph, loadPlaces } from './data/campus'
import { SearchIndex } from './data/search'
import type { Place } from './data/types'
import { buildGraph, nearestNode, type Graph } from './routing/graph'
import { endpointOf, planRoute, routeGeoJSON, straightMeters, MAX_SNAP_M, type Endpoint, type Plan, type PlanError } from './routing/plan'
import { hashParams, useHashRoute } from './state/hashRoute'
import { usePref, useTheme } from './state/prefs'
import { CategoryChips, Featured, PlaceRows } from './features/Browse'
import { PlaceDetail } from './features/PlaceDetail'
import { Directions, type Pick } from './features/Directions'
import { AboutModal, TransitModal } from './features/Modals'

const FEATURED = ['mchenry-library', 'quarry-plaza', 'science-hill', 'baskin-engineering', 'science-engineering-library', 'kresge-college']

export function App() {
  const { mode, setMode, theme } = useTheme()
  const mobile = useMedia(MOBILE_QUERY)
  const [places, setPlaces] = useState<Place[] | null>(null)
  const [graph, setGraph] = useState<Graph | null>(null)
  const [loadError, setLoadError] = useState<string | null>(null)
  const [route, go] = useHashRoute()
  const [q, setQ] = useState('')
  const [cat, setCat] = useState<Category | null>(null)
  const [active, setActive] = useState(0)
  const [detent, setDetent] = useState<Detent>('half')
  const [avoidStairs, setAvoidStairs] = usePref('avoidStairs', false)
  const [reduce, setReduce] = usePref('reduceMotion', false)
  const [solid, setSolid] = usePref('solid', false)
  const [you, setYou] = useState<{ lat: number; lon: number; accuracy: number } | null>(null)
  const [locating, setLocating] = useState(false)
  const [locError, setLocError] = useState<string | null>(null)
  const [bearing, setBearing] = useState(0)
  const [toast, setToast] = useState<string | null>(null)
  const [modal, setModal] = useState<'about' | 'transit' | null>(null)
  const mapRef = useRef<MapHandle>(null)
  const searchRef = useRef<HTMLInputElement>(null)

  useEffect(() => {
    document.documentElement.dataset.motion = reduce ? 'reduce' : ''
    document.documentElement.dataset.solid = String(solid)
  }, [reduce, solid])

  useEffect(() => {
    Promise.all([loadPlaces(), loadGraph()])
      .then(([p, g]) => {
        setPlaces(p.places)
        setGraph(buildGraph(g))
      })
      .catch((e) => setLoadError(String(e.message ?? e)))
  }, [])

  const index = useMemo(() => (places ? new SearchIndex(places) : null), [places])
  const byId = useMemo(() => new Map(places?.map((p) => [p.id, p]) ?? []), [places])

  const results = useMemo(() => {
    if (!index) return []
    return index.search(q, cat || q ? 60 : 12, cat ?? undefined)
  }, [index, q, cat])
  const showResults = q.trim().length > 0 || cat !== null

  const selected = route.name === 'place' ? byId.get(route.id) ?? null : null

  /* ---- directions state from the URL */
  const resolve = useCallback(
    (id?: string): { pick: Pick; ep: Endpoint | null } => {
      if (!id) return { pick: null, ep: null }
      if (id === 'me') return { pick: { id, name: 'My location' }, ep: you ? { id: 'me', name: 'My location', lat: you.lat, lon: you.lon, isLocation: true } : null }
      const p = byId.get(id)
      return p ? { pick: { id, name: p.name }, ep: endpointOf(p) } : { pick: null, ep: null }
    },
    [byId, you],
  )
  const dFrom = route.name === 'directions' ? resolve(route.from) : { pick: null, ep: null }
  const dTo = route.name === 'directions' ? resolve(route.to) : { pick: null, ep: null }

  const { plan, planError } = useMemo((): { plan: Plan | null; planError: PlanError | null } => {
    if (route.name !== 'directions' || !graph || !dFrom.ep || !dTo.ep) return { plan: null, planError: null }
    const r = planRoute(graph, dFrom.ep, dTo.ep, { avoidStairs })
    return 'error' in r ? { plan: null, planError: r.error } : { plan: r, planError: null }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [route, graph, avoidStairs, dFrom.ep?.id, dFrom.ep?.lat, dTo.ep?.id])

  const routeJson = useMemo(() => (plan && graph ? routeGeoJSON(graph, plan) : null), [plan, graph])
  const endpoints = useMemo((): GeoJSON.FeatureCollection | null => {
    if (!plan) return null
    return {
      type: 'FeatureCollection',
      features: [
        { type: 'Feature', properties: { role: 'from' }, geometry: { type: 'Point', coordinates: [plan.originPoint[1], plan.originPoint[0]] } },
        { type: 'Feature', properties: { role: 'to' }, geometry: { type: 'Point', coordinates: [plan.destPoint[1], plan.destPoint[0]] } },
      ],
    }
  }, [plan])

  /* ---- camera */
  const sheetPad = detent === 'peek' ? 160 : Math.round(window.innerHeight * (detent === 'half' ? 0.46 : 0.46))
  const padding = mobile ? { top: 60, bottom: sheetPad, left: 0, right: 0 } : { top: 0, bottom: 0, left: 424, right: 0 }
  const padRef = useRef(padding)
  padRef.current = padding

  useEffect(() => {
    if (selected) mapRef.current?.flyToPlace(selected)
  }, [selected?.id])
  useEffect(() => {
    if (!plan || !graph) return
    const coords = plan.route.nodes.map((n) => [graph.lon[n], graph.lat[n]] as [number, number])
    coords.push([plan.originPoint[1], plan.originPoint[0]], [plan.destPoint[1], plan.destPoint[0]])
    mapRef.current?.fitCoords(coords)
  }, [plan])

  useEffect(() => {
    setDetent(route.name === 'home' ? (mobile ? 'peek' : 'half') : 'half')
  }, [route.name, mobile])

  /* ---- actions */
  const openPlace = (p: Place) => {
    go({ name: 'place', id: p.id })
    setQ('')
    searchRef.current?.blur()
  }
  const home = () => {
    go({ name: 'home' })
    setQ('')
  }
  const flash = (m: string) => {
    setToast(m)
    window.setTimeout(() => setToast(null), 2400)
  }
  const share = async () => {
    const url = location.href
    try {
      if (navigator.share && mobile) await navigator.share({ title: selected?.name ?? 'UCSC Map', url })
      else {
        await navigator.clipboard.writeText(url)
        flash('Link copied')
      }
    } catch {
      flash('Could not copy the link')
    }
  }
  const locate = () => {
    if (!navigator.geolocation) return setLocError('This browser does not support location.')
    setLocating(true)
    setLocError(null)
    navigator.geolocation.getCurrentPosition(
      (pos) => {
        const y = { lat: pos.coords.latitude, lon: pos.coords.longitude, accuracy: pos.coords.accuracy }
        setYou(y)
        setLocating(false)
        const near = graph ? nearestNode(graph, y.lat, y.lon).dist <= MAX_SNAP_M : false
        if (route.name === 'directions') go({ ...route, from: 'me' }, undefined, true)
        else if (!near) flash("You're not on the mapped campus paths")
        else mapRef.current?.flyToLngLat(y.lon, y.lat, 17)
      },
      (err) => {
        setLocating(false)
        setLocError(err.code === err.PERMISSION_DENIED ? 'Location permission was denied. Enable it in your browser settings to use it here.' : 'Your location could not be determined.')
        if (route.name !== 'directions') flash('Location unavailable')
      },
      { enableHighAccuracy: true, timeout: 10000, maximumAge: 30000 },
    )
  }
  const directionsFor = (to?: string) => go({ name: 'directions', from: you ? 'me' : undefined, to })

  const nearGraph = (p: Place) => (graph ? nearestNode(graph, p.lat, p.lon).dist <= MAX_SNAP_M : true)

  /* ---- keyboard on search */
  const nav = (d: 1 | -1) => setActive((a) => Math.max(0, Math.min(results.length - 1, a + d)))
  useEffect(() => setActive(0), [q, cat])
  const submit = () => {
    const p = results[active]
    if (p) openPlace(p)
  }
  useEffect(() => {
    const on = (e: KeyboardEvent) => {
      if (e.key === '/' && document.activeElement?.tagName !== 'INPUT') (e.preventDefault(), searchRef.current?.focus())
    }
    window.addEventListener('keydown', on)
    return () => window.removeEventListener('keydown', on)
  }, [])
  useEffect(() => {
    const p = hashParams().get('q')
    if (p) setQ(p)
  }, [])

  const featured = useMemo(() => FEATURED.map((id) => byId.get(id)).filter((p): p is Place => !!p), [byId])

  /* ---- panel content */
  let content
  if (loadError) content = <GlassBanner tone="danger" title="Campus data failed to load">{loadError}. Check your connection and reload.</GlassBanner>
  else if (!places || !index) content = <div className="center"><Spinner label="Loading campus data" /></div>
  else if (route.name === 'place' && selected)
    content = <PlaceDetail place={selected} nearGraph={nearGraph(selected)} onBack={home} onDirections={() => directionsFor(selected.id)} onShare={share} onTransit={() => setModal('transit')} />
  else if (route.name === 'place')
    content = <GlassBanner tone="warning" title="Place not found" action={<GlassIconButton icon="close" label="Back" size="s" onClick={home} />}>No place has the id "{route.id}".</GlassBanner>
  else if (route.name === 'directions')
    content = (
      <Directions
        from={dFrom.pick}
        to={dTo.pick}
        plan={plan}
        error={planError}
        avoidStairs={avoidStairs}
        onAvoidStairs={setAvoidStairs}
        onPickFrom={(p) => go({ name: 'directions', from: p?.id, to: route.to }, undefined, true)}
        onPickTo={(p) => go({ name: 'directions', from: route.from, to: p?.id }, undefined, true)}
        onSwap={() => go({ name: 'directions', from: route.to, to: route.from }, undefined, true)}
        onClose={() => (route.to && byId.get(route.to) ? go({ name: 'place', id: route.to }) : home())}
        index={index}
        hasLocation={!!you}
        onLocate={locate}
        locating={locating}
        locationError={locError}
        straightMeters={dFrom.ep && dTo.ep ? straightMeters(dFrom.ep, dTo.ep) : null}
      />
    )
  else if (showResults)
    content = (
      <>
        {cat === 'transit' && (
          <button className="rowlink" onClick={() => setModal('transit')}>
            Campus shuttles and METRO →
          </button>
        )}
        <PlaceRows places={results} activeId={results[active]?.id} onPick={openPlace} listId="results" label="Search results" />
      </>
    )
  else content = <Featured places={featured} onPick={openPlace} onTransit={() => setModal('transit')} />

  const searchBar = (
    <div className="searchbar">
      <GlassSearch
        inputRef={searchRef}
        label="Search UCSC"
        placeholder="Search buildings, dining, parking…"
        value={q}
        onChange={(v) => {
          setQ(v)
          if (route.name !== 'home') go({ name: 'home' }, undefined, true)
        }}
        onFocus={() => mobile && setDetent('full')}
        onSubmit={submit}
        onNav={nav}
        onEscape={() => (setQ(''), searchRef.current?.blur())}
        listId="results"
        activeId={results[active] ? `opt-${results[active].id}` : undefined}
        expanded={showResults}
      />
      <CategoryChips value={cat} onChange={(c) => (setCat(c), route.name !== 'home' && go({ name: 'home' }, undefined, true))} />
    </div>
  )

  const panel = (
    <>
      {route.name !== 'directions' && searchBar}
      <div className="panelbody">{content}</div>
    </>
  )

  return (
    <div className="app">
      <MapView
        ref={mapRef}
        theme={theme}
        places={places ?? []}
        selected={selected}
        route={routeJson}
        endpoints={endpoints}
        you={you}
        padding={padding}
        onSelect={(id) => go({ name: 'place', id })}
        onBearing={setBearing}
      />

      {!mobile ? (
        <GlassPanel as="aside" className="side" aria-label="Search and details">
          {panel}
        </GlassPanel>
      ) : (
        <GlassSheet detent={detent} onDetent={setDetent} label="Search and details">
          {panel}
        </GlassSheet>
      )}

      <GlassToolbar label="Map controls" className="controls">
        <GlassTooltip text="Zoom in"><GlassIconButton icon="plus" label="Zoom in" onClick={() => mapRef.current?.zoomBy(1)} /></GlassTooltip>
        <GlassTooltip text="Zoom out"><GlassIconButton icon="minus" label="Zoom out" onClick={() => mapRef.current?.zoomBy(-1)} /></GlassTooltip>
        {Math.abs(bearing) > 1 && <GlassTooltip text="Reset north"><GlassIconButton icon="compass" label="Reset north" onClick={() => mapRef.current?.resetNorth()} /></GlassTooltip>}
        <GlassTooltip text="My location"><GlassIconButton icon="locate" label="Show my location" onClick={locate} aria-busy={locating} /></GlassTooltip>
        <GlassTooltip text="Settings and about"><GlassIconButton icon="info" label="Settings and about" onClick={() => setModal('about')} /></GlassTooltip>
      </GlassToolbar>

      {toast && (
        <div className="toast">
          <GlassPanel elevation="raised" className="toast__in" role="status">{toast}</GlassPanel>
        </div>
      )}
      <TransitModal open={modal === 'transit'} onClose={() => setModal(null)} />
      <AboutModal open={modal === 'about'} onClose={() => setModal(null)} mode={mode} onMode={setMode} reduceMotion={reduce} onReduceMotion={setReduce} solid={solid} onSolid={setSolid} />
    </div>
  )
}
