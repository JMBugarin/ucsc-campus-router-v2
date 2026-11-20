import { useCallback, useEffect, useMemo, useRef, useState } from 'react'
import { MapView, type MapFocus, type MapHandle } from './map/MapView'
import { GlassBanner, GlassIconButton, GlassPanel, GlassSearch, GlassSheet, GlassToolbar, GlassTooltip, Spinner, type Detent } from './design/components'
import { useMedia } from './design/motion'
import { MOBILE_QUERY } from './design/tokens'
import type { Category } from './design/tokens'
import { loadGraph, loadPlaces } from './data/campus'
import { SearchIndex } from './data/search'
import type { Place } from './data/types'
import { buildGraph, nearestNode, type Graph } from './routing/graph'
import type { GraphFile } from './data/types'
import { endpointOf, planCoords, planRoute, routeGeoJSON, straightMeters, MAX_SNAP_M, type Endpoint, type Plan, type PlanError, type RouteFeature } from './routing/plan'
import { hashParams, useHashRoute } from './state/hashRoute'
import { usePref, useTheme } from './state/prefs'
import { CategoryChips, Featured, HousingList, PlaceRows } from './features/Browse'
import { PlaceDetail } from './features/PlaceDetail'
import { MissingRoom } from './features/Feedback'
import { Today } from './features/classes/Today'
import { Schedule } from './features/classes/Schedule'
import { ClassEditor } from './features/classes/ClassEditor'
import { ImportReview, PasteImport, PictureImport, toMeetings } from './features/classes/Import'
import { loadClassesData, makeWalk, placeFor, useNow, type ClassesData } from './schedule/data'
import { schedule, useReminderPrefs, useSchedule } from './schedule/store'
import { useClassReminders, askToNotify } from './schedule/notify'
import { draftFromMeeting, newDraft, toMeeting, type ClassDraft } from './schedule/draft'
import { label as classLabel, planDay } from './schedule/dayPlan'
import { termFor } from './schedule/terms'
import { clockAt, pacificDate } from './schedule/time'
import { GlassSegmentedControl } from './design/components'
import { Directions, type Mode, type Pick } from './features/Directions'
import { AboutModal, TransitModal } from './features/Modals'
import { activity } from './state/activity'
import { loadTransit, useClock, useLive } from './transit/useTransit'
import { useLiveBuses } from './transit/useLiveBuses'
import { prepareNetwork, type MetroFile, type Network } from './transit/raptor'
import { planTrips, tripGeoJSON, type TripOption } from './transit/trip'
import { parsePointId, pointId } from './data/geocode'
import { getPosition, type Help } from './state/location'
import { Tracker, metres as fixMetres, replan } from './state/tracking'
import { LocationHelp } from './features/LocationHelp'
import { recent as recentVehicle } from './transit/liveClient'
import { haversine } from './routing/graph'
import type { TransitData } from './transit/schedule'
import { recentStore } from './data/rooms'
import { audit, roomKey, useDraft } from './state/audit'

const recents = recentStore()

function auditRequested(): boolean {
  try {
    if (hashParams().has('audit')) sessionStorage.setItem('audit', '1')
    return sessionStorage.getItem('audit') === '1'
  } catch {
    return hashParams().has('audit')
  }
}

async function currentFix(): Promise<[number, number] | null> {
  const r = await getPosition()
  return 'pos' in r ? [r.pos.coords.latitude, r.pos.coords.longitude] : null
}

const FEATURED = ['mchenry-library', 'quarry-plaza', 'science-hill', 'baskin-engineering', 'science-engineering-library', 'kresge-college']

export function App() {
  const { mode, setMode, theme } = useTheme()
  const mobile = useMedia(MOBILE_QUERY)
  const [places, setPlaces] = useState<Place[] | null>(null)
  const [graph, setGraph] = useState<Graph | null>(null)
  const [transit, setTransit] = useState<TransitData | null>(null)
  const [loadError, setLoadError] = useState<string | null>(null)
  const [route, go] = useHashRoute()
  const [q, setQ] = useState('')
  const [cat, setCat] = useState<Category | null>(null)
  const [active, setActive] = useState(0)
  const [detent, setDetent] = useState<Detent>('half')
  const [avoidStairs, setAvoidStairs] = usePref('avoidStairs', false)
  const [reduce, setReduce] = usePref('reduceMotion', false)
  const [solid, setSolid] = usePref('solid', false)
  const [you, setYou] = useState<{ lat: number; lon: number; accuracy: number; heading?: number | null; at?: number } | null>(null)
  const [locationOn, setLocationOn] = usePref('locationOn', false)
  const [homeId, setHomeId] = usePref<string | null>('homePlace', null)
  const [modePref, setModePref] = usePref<Mode>('travelMode', 'walk')
  const [follow, setFollow] = useState(true)
  const [origin, setOrigin] = useState<{ lat: number; lon: number; at: number } | null>(null)
  const tracker = useRef<Tracker | null>(null)
  const [locating, setLocating] = useState(false)
  const [locError, setLocError] = useState<string | null>(null)
  const [locHelp, setLocHelp] = useState<Help | null>(null)
  const [bearing, setBearing] = useState(0)
  const [toast, setToast] = useState<string | null>(null)
  const [modal, setModal] = useState<'about' | 'transit' | null>(null)
  const [recentIds, setRecentIds] = useState<string[]>(() => recents.get())
  const [auditMode] = useState(auditRequested)
  const [classes, setClasses] = useState<ClassesData | null>(null)
  const [metro, setMetro] = useState<Network | null>(null)
  const [town, setTown] = useState<Graph | null>(null)
  const [pointNames, setPointNames] = useState<Map<string, string>>(() => new Map())
  const [pickPoint, setPickPoint] = useState<'from' | 'to' | null>(null)
  const [tripIndex, setTripIndex] = useState(0)
  const meetings = useSchedule()
  const reminderPrefs = useReminderPrefs()
  const now = useNow()
  const [sheet, setSheet] = useState<null | { kind: 'paste' } | { kind: 'picture'; file: File } | { kind: 'review'; drafts: ClassDraft[]; notes: string[] } | { kind: 'edit'; index: number | null; draft: ClassDraft }>(null)
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
      .then(() => loadClassesData().then(setClasses, () => undefined))
      .then(() => loadTransit().then(setTransit, () => undefined))
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
  const draft = useDraft(auditMode && selected?.kind === 'room' ? roomKey(selected) : null)
  const focus = useMemo((): MapFocus | null => {
    if (!selected) return null
    const building = selected.kind === 'room' && selected.room ? byId.get(selected.room.building) : selected
    if (!building?.roomIds?.length) return null
    const d = selected.room?.door
    return {
      rooms: building.roomIds.map((id) => byId.get(id)).filter((p): p is Place => !!p),
      doors: building.entrances ?? [],
      door: draft?.door ?? (d ? [d.lat, d.lon] : null),
    }
  }, [selected, byId, draft?.door])
  const roomOf = (id?: string) => {
    const p = id ? byId.get(id) : undefined
    return p?.kind === 'room' ? p : null
  }

  /* ---- directions state from the URL */
  const resolve = useCallback(
    (id?: string): { pick: Pick; ep: Endpoint | null } => {
      if (!id) return { pick: null, ep: null }
      if (id === 'me') {
        const at = origin ?? you
        return { pick: { id, name: 'My location' }, ep: at ? { id: 'me', name: 'My location', lat: at.lat, lon: at.lon, isLocation: true } : null }
      }
      const pt = parsePointId(id)
      if (pt) {
        const name = pointNames.get(id) ?? 'Dropped pin'
        return { pick: { id, name }, ep: { id, name, lat: pt[0], lon: pt[1] } }
      }
      const p = byId.get(id)
      return p ? { pick: { id, name: p.name }, ep: endpointOf(p) } : { pick: null, ep: null }
    },
    [byId, you, origin, pointNames],
  )
  const dFrom = route.name === 'directions' ? resolve(route.from) : { pick: null, ep: null }
  const dTo = route.name === 'directions' ? resolve(route.to) : { pick: null, ep: null }

  const { plan, planError } = useMemo((): { plan: Plan | null; planError: PlanError | null } => {
    if (route.name !== 'directions' || !graph || !dFrom.ep || !dTo.ep) return { plan: null, planError: null }
    const r = planRoute(graph, dFrom.ep, dTo.ep, { avoidStairs })
    return 'error' in r ? { plan: null, planError: r.error } : { plan: r, planError: null }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [route, graph, avoidStairs, dFrom.ep?.id, dFrom.ep?.lat, dFrom.ep?.lon, dTo.ep?.id, dTo.ep?.lat, dTo.ep?.lon])

  const showsTimes = route.name === 'directions' || (route.name === 'place' && !!byId.get(route.id)?.stops)
  const clock = useClock(showsTimes)
  const live = useLive(showsTimes)

  const toRoom = route.name === 'directions' ? roomOf(route.to) : null
  const fromRoom = route.name === 'directions' ? roomOf(route.from) : null
  const arriveBy = useMemo(() => {
    if (route.name !== 'directions') return null
    const p = hashParams()
    const at = Number(p.get('arrive'))
    return at > 0 ? { at, label: p.get('cls') ?? 'class' } : null
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [route])
  // bus trips for every trip, so anyone who would rather ride can, even when walking is quicker
  const wantTrips = route.name === 'directions' && !!dFrom.ep && !!dTo.ep && planError !== 'same-place'
  useEffect(() => {
    if (!wantTrips || metro) return
    fetch(`${import.meta.env.BASE_URL}data/metro.json`)
      .then((r) => (r.ok ? r.json() : Promise.reject(new Error(String(r.status)))))
      .then((f: MetroFile) => setMetro(prepareNetwork(f)))
      .catch(() => undefined)
  }, [wantTrips, metro])
  // the town street network, for the walk to and from the bus when one end is off campus
  const needTown = wantTrips && (planError === 'no-path-near-origin' || planError === 'no-path-near-destination')
  useEffect(() => {
    if (!needTown || town) return
    fetch(`${import.meta.env.BASE_URL}data/town.json`)
      .then((r) => (r.ok ? r.json() : Promise.reject(new Error(String(r.status)))))
      .then((f: GraphFile) => setTown(buildGraph(f)))
      .catch(() => undefined)
  }, [needTown, town])
  const minute = Math.floor(now / 60000)
  const trips = useMemo((): TripOption[] | null => {
    if (!wantTrips || !metro || !graph || !dFrom.ep || !dTo.ep) return null
    return planTrips(metro, graph, dFrom.ep, dTo.ep, arriveBy ? { kind: 'arrive', by: arriveBy.at, now: minute * 60000 } : { kind: 'leave', at: minute * 60000 }, avoidStairs, town, plan ? { walkOnly: plan.seconds } : null)
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [wantTrips, metro, graph, town, dFrom.ep?.id, dFrom.ep?.lat, dFrom.ep?.lon, dTo.ep?.id, dTo.ep?.lat, dTo.ep?.lon, arriveBy?.at, minute, avoidStairs, plan?.seconds])
  useEffect(() => setTripIndex(0), [dFrom.ep?.id, dTo.ep?.id, arriveBy?.at])
  // walk or ride: what this trip was set to, else what was chosen last time, else the bus for a long walk
  const [modeChoice, setModeChoice] = useState<Mode | null>(null)
  useEffect(() => setModeChoice(null), [route.name === 'directions' ? route.from : '', route.name === 'directions' ? route.to : ''])
  const wanted: Mode = modeChoice ?? (modePref === 'bus' || (!!plan && plan.seconds > 30 * 60) ? 'bus' : 'walk')
  const travel: Mode = !plan ? 'bus' : wanted === 'bus' && trips?.length !== 0 ? 'bus' : 'walk'
  const chooseMode = (m: Mode) => {
    setModeChoice(m)
    setModePref(m)
  }
  const trip = travel === 'bus' && trips?.length ? trips[Math.min(tripIndex, trips.length - 1)] : null
  const stopPlace = route.name === 'place' && selected?.stops ? selected : null
  const liveBuses = useLiveBuses(!!stopPlace || (route.name === 'directions' && !!trip))
  const busPins = useMemo(() => {
    const nowSecs = Math.floor(now / 1000)
    const trips = new Set(route.name === 'directions' ? (trip?.parts ?? []).flatMap((p) => (p.kind === 'bus' ? [p.tripId] : [])) : [])
    const label = (v: { route?: string }) => (v.route && transit?.routes[v.route]?.n) || v.route || '•'
    return liveBuses.vehicles
      .filter((v) => recentVehicle(v, nowSecs) && (trips.has(v.trip ?? '') || (stopPlace && haversine(stopPlace.lat, stopPlace.lon, v.lat, v.lon) < 1500)))
      .map((v) => ({ id: v.id, lat: v.lat, lon: v.lon, label: label(v), bearing: v.bearing, highlight: trips.has(v.trip ?? '') }))
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [liveBuses.vehicles, trip, stopPlace?.id, now, transit, route.name])
  const routeJson = useMemo(() => {
    if (trip && graph) return tripGeoJSON(graph, trip)
    if (!plan || !graph) return null
    const fc = routeGeoJSON(graph, plan)
    const indoor = (a: [number, number], b: [number, number]): RouteFeature => ({ type: 'Feature', properties: { kind: 'indoor' }, geometry: { type: 'LineString', coordinates: [[a[1], a[0]], [b[1], b[0]]] } })
    if (toRoom) fc.features.push(indoor(plan.destPoint, [toRoom.lat, toRoom.lon]))
    if (fromRoom) fc.features.push(indoor([fromRoom.lat, fromRoom.lon], plan.originPoint))
    return fc
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [plan, graph, toRoom?.id, fromRoom?.id, trip])
  const endpoints = useMemo((): GeoJSON.FeatureCollection | null => {
    if (trip && dFrom.ep && dTo.ep) {
      const pt = (role: string, lat: number, lon: number) => ({ type: 'Feature' as const, properties: { role }, geometry: { type: 'Point' as const, coordinates: [lon, lat] } })
      return {
        type: 'FeatureCollection',
        features: [
          pt('from', dFrom.ep.lat, dFrom.ep.lon),
          pt('to', dTo.ep.lat, dTo.ep.lon),
          ...trip.parts.flatMap((p) => (p.kind === 'bus' ? [pt('board', ...p.stops[0]), pt('alight', ...p.stops[p.stops.length - 1])] : [])),
          ...[toRoom].filter((r): r is Place => !!r).map((r) => pt('room', r.lat, r.lon)),
        ],
      }
    }
    if (!plan) return null
    return {
      type: 'FeatureCollection',
      features: [
        { type: 'Feature', properties: { role: 'from' }, geometry: { type: 'Point', coordinates: [plan.originPoint[1], plan.originPoint[0]] } },
        { type: 'Feature', properties: { role: 'to' }, geometry: { type: 'Point', coordinates: [plan.destPoint[1], plan.destPoint[0]] } },
        ...[toRoom, fromRoom].filter((r): r is Place => !!r).map((r) => ({ type: 'Feature' as const, properties: { role: 'room' }, geometry: { type: 'Point' as const, coordinates: [r.lon, r.lat] } })),
      ],
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [plan, toRoom?.id, fromRoom?.id, trip])

  /* ---- camera */
  const sheetPad = detent === 'peek' ? 160 : Math.round(window.innerHeight * (detent === 'half' ? 0.46 : 0.46))
  const padding = mobile ? { top: 60, bottom: sheetPad, left: 0, right: 0 } : { top: 0, bottom: 0, left: 424, right: 0 }
  const padRef = useRef(padding)
  padRef.current = padding

  useEffect(() => {
    if (!selected) return
    const d = selected.room?.door
    if (d) mapRef.current?.fitCoords([[selected.lon, selected.lat], [d.lon, d.lat]], 18.6)
    else mapRef.current?.flyToPlace(selected, selected.roomIds?.length ? 17.8 : undefined)
    void activity.meaningfulAction()
    setRecentIds(recents.push(selected.id))
  }, [selected?.id])
  useEffect(() => void activity.flush(), [])
  const fitted = useRef('')
  const followedAt = useRef<{ lat: number; lon: number } | null>(null)
  useEffect(() => {
    const key = route.name === 'directions' ? `${route.from}>${route.to}|${tripIndex}|${trip ? 'bus' : 'walk'}` : ''
    // once a live trip is framed, later redraws leave the camera to the follow mode
    if (key && fitted.current === key && route.name === 'directions' && route.from === 'me') return
    if (!plan && !trip) return
    fitted.current = key
    followedAt.current = you ? { lat: you.lat, lon: you.lon } : null
    if (trip && dFrom.ep && dTo.ep) {
      mapRef.current?.fitCoords([[dFrom.ep.lon, dFrom.ep.lat], [dTo.ep.lon, dTo.ep.lat], ...trip.parts.flatMap((p) => (p.kind === 'bus' ? p.stops.map(([la, lo]) => [lo, la] as [number, number]) : []))])
      return
    }
    if (!plan || !graph) return
    const coords = planCoords(plan)
    for (const r of [toRoom, fromRoom]) if (r) coords.push([r.lon, r.lat])
    mapRef.current?.fitCoords(coords)
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [plan, trip?.leave, trip?.arrive])

  /* ---- live location: follow the walker, and redraw the route from where they are */
  const liveTrip = route.name === 'directions' && route.from === 'me'
  const startTracking = useCallback(() => {
    if (!tracker.current)
      tracker.current = new Tracker(
        (f) => setYou({ lat: f.lat, lon: f.lon, accuracy: f.accuracy, heading: f.heading, at: f.at }),
        (code) => {
          if (code !== 1) return
          void getPosition().then((r) => 'help' in r && setLocHelp(r.help))
        },
      )
    tracker.current.start()
  }, [])
  const wantsTracking = locationOn && route.name !== 'schedule' && route.name !== 'gallery'
  useEffect(() => {
    if (!wantsTracking) {
      tracker.current?.stop()
      return
    }
    let cancelled = false
    void (async () => {
      let state: PermissionState | 'unknown' = 'unknown'
      try {
        state = (await navigator.permissions?.query({ name: 'geolocation' }))?.state ?? 'unknown'
      } catch {
        /* not supported */
      }
      // never prompt just for opening the site; a live trip is something the person asked for
      if (!cancelled && state !== 'denied' && (state !== 'prompt' || liveTrip)) startTracking()
    })()
    return () => {
      cancelled = true
    }
  }, [wantsTracking, liveTrip, startTracking])
  useEffect(() => () => tracker.current?.stop(), [])
  useEffect(() => {
    setOrigin(null)
    setFollow(true)
  }, [route.name === 'directions' ? route.from : '', route.name === 'directions' ? route.to : ''])
  const routeLine = useMemo((): [number, number][] => (routeJson ? routeJson.features.flatMap((f) => (f.geometry.type === 'LineString' ? (f.geometry.coordinates as [number, number][]) : [])) : []), [routeJson])
  useEffect(() => {
    if (!liveTrip || !you) return
    const r = replan(origin, { lat: you.lat, lon: you.lon, accuracy: you.accuracy, heading: you.heading ?? null, at: you.at ?? Date.now() }, origin ? routeLine : [])
    if (r.again) {
      setOrigin({ lat: you.lat, lon: you.lon, at: you.at ?? Date.now() })
      if (r.offRoute) flash('Rerouted from where you are')
    }
    if (follow && fitted.current && followedAt.current && fixMetres(followedAt.current, you) >= 8) {
      followedAt.current = { lat: you.lat, lon: you.lon }
      mapRef.current?.follow(you.lon, you.lat)
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [you, liveTrip, routeLine])
  // with location on, directions start from here unless another start was chosen
  useEffect(() => {
    if (route.name === 'directions' && !route.from && locationOn) go({ ...route, from: 'me' }, hashParams().get('arrive') ? Object.fromEntries(hashParams()) : undefined, true)
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [route, locationOn])
  const arrivedAt = useMemo(() => {
    if (!liveTrip || !you || !dTo.ep) return null
    const dest = trip ? { lat: dTo.ep.lat, lon: dTo.ep.lon } : plan ? { lat: plan.destPoint[0], lon: plan.destPoint[1] } : null
    return dest && fixMetres(you, dest) <= Math.max(20, Math.min(you.accuracy, 40)) ? dTo.ep.name : null
  }, [liveTrip, you, dTo.ep, plan, trip])

  useEffect(() => {
    setDetent(route.name === 'home' ? (mobile ? 'peek' : 'half') : route.name === 'schedule' ? 'full' : 'half')
  }, [route.name, mobile])
  useEffect(() => {
    if (!location.hash && schedule.all.length) go({ name: 'today' }, undefined, true)
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [])
  useClassReminders(meetings, classes?.holidays ?? null, reminderPrefs.lead, (t) => flash(t))
  const walk = useMemo(() => (classes ? makeWalk(graph, classes.campus, byId, you, avoidStairs) : () => null), [graph, classes, byId, you, avoidStairs])
  const classPins = useMemo(() => {
    if (route.name !== 'today' || !classes) return []
    const plan = planDay(meetings, now, classes.holidays, route.day && route.day !== pacificDate(now) ? route.day : null)
    return plan.classes.flatMap((o) => {
      const p = placeFor(o.meeting.location, classes.campus, byId)
      return p ? [{ id: p.id, lat: p.lat, lon: p.lon, label: `${clockAt(o.start)} ${classLabel(o)}`, next: plan.next === o }] : []
    })
  }, [route, classes, meetings, now, byId])
  useEffect(() => {
    if (route.name === 'today' && classPins.length) mapRef.current?.fitCoords(classPins.map((c) => [c.lon, c.lat] as [number, number]), 16.5)
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [route.name, route.name === 'today' ? route.day : null, classPins.length])
  const termDates = () => {
    const t = classes ? termFor(classes.terms, pacificDate(Date.now())) : null
    return { startDate: t?.start ?? null, endDate: t?.end ?? null }
  }

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
  function flash(m: string) {
    setToast(m)
    window.setTimeout(() => setToast(null), m.length > 60 ? 6000 : 2400)
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
  const locate = async () => {
    setLocating(true)
    setLocError(null)
    setLocHelp(null)
    const r = await getPosition()
    setLocating(false)
    if (!('pos' in r)) {
      setLocError(`${r.help.title}. ${r.help.body}`)
      setLocHelp(r.help)
      return
    }
    const pos = r.pos
    const y = { lat: pos.coords.latitude, lon: pos.coords.longitude, accuracy: pos.coords.accuracy, heading: null, at: Date.now() }
    setYou(y)
    setLocationOn(true)
    setFollow(true)
    startTracking()
    const near = graph ? nearestNode(graph, y.lat, y.lon).dist <= MAX_SNAP_M : false
    const params = route.name === 'directions' && hashParams().get('arrive') ? Object.fromEntries(hashParams()) : undefined
    if (route.name === 'directions') go({ ...route, from: 'me' }, params, true)
    else if (!near) flash("You're off campus: Get me there plans the bus from here.")
    else mapRef.current?.flyToLngLat(y.lon, y.lat, 17)
  }
  const directionsFor = (to?: string) => go({ name: 'directions', from: you || locationOn ? 'me' : undefined, to })
  const homePlace = homeId ? (byId.get(homeId) ?? null) : null
  const goHome = (from?: Place) => homePlace && go({ name: 'directions', from: from?.id ?? (you || locationOn ? 'me' : undefined), to: homePlace.id })
  const pickHome = () => {
    go({ name: 'home' })
    setQ('')
    setCat('housing')
  }
  const walkHome = (from: Place) => {
    if (!graph || !homePlace) return null
    const r = planRoute(graph, endpointOf(from), endpointOf(homePlace), { avoidStairs })
    return 'error' in r ? null : Math.max(1, Math.round(r.seconds / 60))
  }

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
  const recent = useMemo(() => recentIds.map((id) => byId.get(id)).filter((p): p is Place => !!p), [recentIds, byId])

  /* ---- panel content */
  let content
  if (loadError) content = <GlassBanner tone="danger" title="Campus data failed to load">{loadError}. Check your connection and reload.</GlassBanner>
  else if (!places || !index) content = <div className="center"><Spinner label="Loading campus data" /></div>
  else if (route.name === 'today' && classes)
    content = (
      <Today
        meetings={meetings}
        data={classes}
        byId={byId}
        now={now}
        day={route.day ?? null}
        walk={walk}
        hasLocation={!!you}
        onDay={(d) => go(d ? { name: 'today', day: d } : { name: 'today' }, undefined, true)}
        onOpen={openPlace}
        onGetThere={(o, p) => {
          void activity.meaningfulAction()
          go({ name: 'directions', from: you || locationOn ? 'me' : undefined, to: p.id }, { arrive: String(o.start), cls: classLabel(o) })
        }}
        onSchedule={() => go({ name: 'schedule' })}
        home={homePlace}
        walkHome={walkHome}
        onGoHome={goHome}
        onPickHome={pickHome}
      />
    )
  else if (route.name === 'schedule' && classes)
    content = (
      <Schedule
        meetings={meetings}
        persistent={schedule.persistent}
        reminderLead={reminderPrefs.lead}
        now={now}
        onPaste={() => setSheet({ kind: 'paste' })}
        onPicture={(file) => setSheet({ kind: 'picture', file })}
        onAdd={() => setSheet({ kind: 'edit', index: null, draft: newDraft(termDates()) })}
        onEdit={(i) => setSheet({ kind: 'edit', index: i, draft: draftFromMeeting(meetings[i]) })}
        onReminders={async (lead) => {
          if (lead !== null) {
            const perm = await askToNotify()
            if (perm === 'denied') flash('Notifications are blocked for this site, so reminders will only show on this page.')
          }
          schedule.setReminderLead(lead)
        }}
        onClear={() => schedule.clear()}
      />
    )
  else if ((route.name === 'today' || route.name === 'schedule') && !classes) content = <div className="center"><Spinner label="Loading your classes" /></div>
  else if (route.name === 'place' && selected)
    content = (
      <PlaceDetail
        place={selected}
        byId={byId}
        onOpen={openPlace}
        auditMode={auditMode}
        onLocate={currentFix}
        transit={transit}
        now={clock}
        live={live}
        nearGraph={nearGraph(selected)}
        onBack={home}
        onDirections={() => directionsFor(selected.id)}
        onShare={share}
        onTransit={() => setModal('transit')}
        home={homeId}
        onSetHome={(id) => {
          setHomeId(id)
          flash(id ? 'Saved as your home' : 'Home removed')
        }}
      />
    )
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
        mode={travel}
        onMode={chooseMode}
        toRoom={toRoom}
        arriveBy={arriveBy}
        now={now}
        vehicles={liveBuses.vehicles}
        live={live}
        trips={wantTrips ? trips : null}
        tripsLoading={wantTrips && !trips}
        tripIndex={tripIndex}
        onTrip={setTripIndex}
        picking={pickPoint}
        following={liveTrip ? { finding: !you, arrived: arrivedAt } : null}
        onPickOnMap={(field) => setPickPoint(field)}
        homePlace={homePlace}
        onPickAddress={(field, a) => {
          const id = pointId(a.lat, a.lon)
          setPointNames((m) => new Map(m).set(id, a.label))
          go({ name: 'directions', from: field === 'from' ? id : route.name === 'directions' ? route.from : undefined, to: field === 'to' ? id : route.name === 'directions' ? route.to : undefined }, hashParams().get('arrive') ? Object.fromEntries(hashParams()) : undefined, true)
        }}
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
        {cat === 'housing' && !q.trim() ? (
          <HousingList places={index.search('', 400, 'housing')} onPick={openPlace} />
        ) : (
          <PlaceRows places={results} activeId={results[active]?.id} onPick={openPlace} listId="results" label="Search results" />
        )}
        {q.trim() && (/\d/.test(q) ? !results.some((p) => p.kind === 'room') : !results.length) && <MissingRoom query={q.trim()} />}
      </>
    )
  else content = <Featured places={featured} recent={recent} onPick={openPlace} onTransit={() => setModal('transit')} home={homePlace} onGoHome={() => goHome()} onPickHome={pickHome} />

  const searchBar = (
    <div className="searchbar">
      <GlassSearch
        inputRef={searchRef}
        label="Search UCSC"
        placeholder="Search a room like BE 152, or a building…"
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
      {route.name !== 'place' && <CategoryChips value={cat} onChange={(c) => (setCat(c), route.name !== 'home' && go({ name: 'home' }, undefined, true))} />}
    </div>
  )

  const tab = route.name === 'today' ? 'today' : route.name === 'schedule' ? 'schedule' : 'map'
  const tabs = (
    <div className="tabs">
      <GlassSegmentedControl<'today' | 'schedule' | 'map'>
        label="Classmap sections"
        value={tab}
        onChange={(v) => go(v === 'map' ? { name: 'home' } : { name: v })}
        options={[
          { value: 'today', label: 'Today' },
          { value: 'schedule', label: 'Schedule' },
          { value: 'map', label: 'Map' },
        ]}
      />
    </div>
  )

  const panel = (
    <>
      {route.name !== 'directions' && tabs}
      {tab === 'map' && route.name !== 'directions' && searchBar}
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
        focus={focus}
        classPins={classPins}
        buses={busPins}
        route={routeJson}
        endpoints={endpoints}
        you={you}
        padding={padding}
        onSelect={(id) => go({ name: 'place', id })}
        onUserPan={() => setFollow(false)}
        onMapClick={(lat, lon) => {
          if (pickPoint && route.name === 'directions') {
            const id = pointId(lat, lon)
            setPickPoint(null)
            go({ name: 'directions', from: pickPoint === 'from' ? id : route.from, to: pickPoint === 'to' ? id : route.to }, hashParams().get('arrive') ? Object.fromEntries(hashParams()) : undefined, true)
            return true
          }
          return audit.tap(lat, lon)
        }}
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
        {liveTrip && you && !follow && (
          <GlassTooltip text="Follow me">
            <GlassIconButton
              icon="walk"
              label="Follow my location"
              onClick={() => {
                setFollow(true)
                followedAt.current = { lat: you.lat, lon: you.lon }
                mapRef.current?.follow(you.lon, you.lat)
              }}
            />
          </GlassTooltip>
        )}
        <GlassTooltip text="Settings and about"><GlassIconButton icon="info" label="Settings and about" onClick={() => setModal('about')} /></GlassTooltip>
      </GlassToolbar>

      {toast && (
        <div className="toast">
          <GlassPanel elevation="raised" className="toast__in" role="status">{toast}</GlassPanel>
        </div>
      )}
      <TransitModal open={modal === 'transit'} onClose={() => setModal(null)} />
      {locHelp && (
        <LocationHelp
          help={locHelp}
          onClose={() => setLocHelp(null)}
          onRetry={() => void locate()}
          onPickOnMap={
            route.name === 'directions'
              ? () => {
                  setLocHelp(null)
                  setPickPoint('from')
                }
              : undefined
          }
        />
      )}
      {classes && index && sheet?.kind === 'paste' && <PasteImport campus={classes.campus} onClose={() => setSheet(null)} onRead={(drafts, notes) => setSheet({ kind: 'review', drafts: drafts.map((d) => ({ ...d, ...(d.startDate ? {} : termDates()) })), notes })} />}
      {classes && sheet?.kind === 'picture' && <PictureImport file={sheet.file} onClose={() => setSheet(null)} onRead={(drafts, notes) => setSheet({ kind: 'review', drafts: drafts.map((d) => ({ ...d, ...(d.startDate ? {} : termDates()) })), notes })} />}
      {classes && index && sheet?.kind === 'review' && (
        <ImportReview
          drafts={sheet.drafts}
          notes={sheet.notes}
          campus={classes.campus}
          byId={byId}
          index={index}
          onClose={() => setSheet(null)}
          onSave={(drafts) => {
            const added = schedule.add(toMeetings(drafts))
            setSheet(null)
            flash(added === drafts.length ? `Added ${added} ${added === 1 ? 'class' : 'classes'}` : `Added ${added}; ${drafts.length - added} were already saved`)
            go({ name: 'today' })
          }}
        />
      )}
      {classes && index && sheet?.kind === 'edit' && (
        <ClassEditor
          draft={sheet.draft}
          title={sheet.index === null ? 'Add a class' : 'Edit class'}
          campus={classes.campus}
          byId={byId}
          index={index}
          onClose={() => setSheet(null)}
          onDelete={sheet.index === null ? undefined : () => (schedule.remove(sheet.index!), setSheet(null))}
          onSave={(d) => {
            if (sheet.index === null) schedule.add([toMeeting(d)])
            else schedule.replace(sheet.index, toMeeting(d))
            setSheet(null)
          }}
        />
      )}
      <AboutModal
        open={modal === 'about'}
        onClose={() => setModal(null)}
        mode={mode}
        onMode={setMode}
        reduceMotion={reduce}
        onReduceMotion={setReduce}
        solid={solid}
        onSolid={setSolid}
        homeName={homePlace?.name ?? null}
        onClearHome={() => setHomeId(null)}
        onPickHome={() => {
          setModal(null)
          pickHome()
        }}
        locationOn={locationOn}
        onLocationOn={(v) => {
          setLocationOn(v)
          if (!v) {
            tracker.current?.stop()
            setYou(null)
            setOrigin(null)
          }
        }}
      />
    </div>
  )
}
