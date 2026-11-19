import { forwardRef, useEffect, useImperativeHandle, useRef } from 'react'
import * as maplibregl from 'maplibre-gl'
import type { GeoJSONSource, Map as MLMap, PaddingOptions } from 'maplibre-gl'
import 'maplibre-gl/dist/maplibre-gl.css'
import { buildStyle, type Theme } from './style'
import { addMarkerImages } from './markers'
import { CAMPUS_CENTER } from '../data/campus'
import type { Place } from '../data/types'
import { notifyBackdrop, setBackdropSource } from '../design/adaptive'
import { CameraMotion } from '../design/tokens'
import { prefersReducedMotion } from '../design/motion'

maplibregl.setWorkerUrl(new URL(`${import.meta.env.BASE_URL}maplibre/maplibre-gl-worker.mjs`, location.href).href)

const RANK: Record<string, number> = { college: 0, library: 1, landmark: 2, academic: 3, dining: 4, transit: 5, parking: 6, room: 7, housing: 8 }

export interface MapHandle {
  flyToPlace(p: Place, zoom?: number): void
  fitCoords(coords: [number, number][], maxZoom?: number): void
  flyToLngLat(lng: number, lat: number, zoom?: number): void
  resetNorth(): void
  zoomBy(d: number): void
  getMap(): MLMap | null
  setCamera(c: { lng: number; lat: number; zoom: number; bearing?: number; pitch?: number }): void
  /** keeps the walker in view while following them */
  follow(lng: number, lat: number): void
}

/** A building's classrooms and doors, drawn when it or one of its rooms is open. */
export interface MapFocus {
  rooms: Place[]
  doors: [number, number][]
  /** the door the open room's directions end at */
  door: [number, number] | null
}

export interface MapViewProps {
  theme: Theme
  places: Place[]
  selected: Place | null
  focus?: MapFocus | null
  /** buses on the map: a trip's own bus is highlighted */
  buses?: { id: string; lat: number; lon: number; label: string; bearing?: number; highlight: boolean }[]
  /** today's classes, pinned with their start times */
  classPins?: { id: string; lat: number; lon: number; label: string; next: boolean }[]
  route: GeoJSON.FeatureCollection | null
  endpoints: GeoJSON.FeatureCollection | null
  you: { lat: number; lon: number; accuracy: number } | null
  padding: PaddingOptions
  onSelect: (id: string) => void
  /** the person moved the map themselves (so stop following them) */
  onUserPan?: () => void
  /** a tap on the map itself; return true to keep it from also opening a place */
  onMapClick?: (lat: number, lon: number) => boolean
  onBearing?: (b: number) => void
  onReady?: () => void
  interactive?: boolean
  initial?: { lng: number; lat: number; zoom: number }
}

const EMPTY: GeoJSON.FeatureCollection = { type: 'FeatureCollection', features: [] }

function focusFeatures(f: MapFocus | null | undefined, selected: Place | null): { rooms: GeoJSON.FeatureCollection; doors: GeoJSON.FeatureCollection } {
  if (!f) return { rooms: EMPTY, doors: EMPTY }
  const same = (a: [number, number], b: [number, number] | null) => !!b && Math.abs(a[0] - b[0]) < 1e-6 && Math.abs(a[1] - b[1]) < 1e-6
  const doors = f.doors.filter((d) => !same(d, f.door)).map((d) => ({ d, chosen: 0 }))
  const floors = new Set(f.rooms.map((r) => r.room?.floor?.label))
  if (f.door) doors.push({ d: f.door, chosen: 1 })
  return {
    rooms: {
      type: 'FeatureCollection',
      features: f.rooms
        .filter((r) => r.id !== selected?.id)
        .map((r) => ({ type: 'Feature', properties: { id: r.id, label: floors.size > 1 && r.room?.floor ? `${r.room.number} · F${r.room.floor.label}` : r.room?.number ?? '' }, geometry: { type: 'Point', coordinates: [r.lon, r.lat] } })),
    },
    doors: {
      type: 'FeatureCollection',
      features: doors.map(({ d, chosen }) => ({ type: 'Feature', properties: { chosen }, geometry: { type: 'Point', coordinates: [d[1], d[0]] } })),
    },
  }
}

function placeFeatures(places: Place[]): GeoJSON.FeatureCollection {
  return {
    type: 'FeatureCollection',
    features: places.map((p) => ({
      type: 'Feature',
      id: undefined,
      properties: { id: p.id, name: p.name, label: p.short ?? p.name, kind: p.kind, rank: RANK[p.kind] ?? 9 },
      geometry: { type: 'Point', coordinates: [p.lon, p.lat] },
    })),
  }
}

export const MapView = forwardRef<MapHandle, MapViewProps>(function MapView(props, ref) {
  const el = useRef<HTMLDivElement>(null)
  const mapRef = useRef<MLMap | null>(null)
  const propsRef = useRef(props)
  propsRef.current = props
  const themeApplied = useRef<Theme | null>(null)

  const apply = () => {
    const map = mapRef.current
    const p = propsRef.current
    if (!map) return
    if (!map.isStyleLoaded()) {
      map.once('idle', apply)
      return
    }
    const set = (id: string, d: GeoJSON.FeatureCollection) => (map.getSource(id) as GeoJSONSource | undefined)?.setData(d)
    set('places', placeFeatures(p.places.filter((x) => x.kind !== 'parking' && x.kind !== 'room')))
    const f = focusFeatures(p.focus, p.selected)
    set('rooms', f.rooms)
    set('doors', f.doors)
    set('buses', {
      type: 'FeatureCollection',
      features: (p.buses ?? []).map((b) => ({ type: 'Feature', properties: { id: b.id, label: b.label, hi: b.highlight ? 1 : 0 }, geometry: { type: 'Point', coordinates: [b.lon, b.lat] } })),
    })
    set('classes', {
      type: 'FeatureCollection',
      features: (p.classPins ?? []).map((c) => ({ type: 'Feature', properties: { id: c.id, label: c.label, next: c.next ? 1 : 0 }, geometry: { type: 'Point', coordinates: [c.lon, c.lat] } })),
    })
    set('parking', placeFeatures(p.places.filter((x) => x.kind === 'parking')))
    set('route', p.route ?? EMPTY)
    set('endpoints', p.endpoints ?? EMPTY)
    set('selected', p.selected ? placeFeatures([p.selected]) : EMPTY)
    set(
      'you',
      p.you
        ? {
            type: 'FeatureCollection',
            features: [{ type: 'Feature', properties: { accuracy_px: Math.min(80, Math.max(10, p.you.accuracy / 1.2)) }, geometry: { type: 'Point', coordinates: [p.you.lon, p.you.lat] } }],
          }
        : EMPTY,
    )
  }

  useEffect(() => {
    const p = propsRef.current
    const map = new maplibregl.Map({
      container: el.current!,
      style: buildStyle(p.theme),
      center: p.initial ? [p.initial.lng, p.initial.lat] : CAMPUS_CENTER,
      zoom: p.initial?.zoom ?? 15.3,
      minZoom: 11,
      maxZoom: 19.5,
      maxPitch: 60,
      attributionControl: false,
      canvasContextAttributes: { preserveDrawingBuffer: true, antialias: true },
      interactive: p.interactive !== false,
      fadeDuration: 120,
      dragRotate: true,
    })
    themeApplied.current = p.theme
    mapRef.current = map
    map.addControl(new maplibregl.AttributionControl({ compact: true }), 'bottom-right')
    setBackdropSource(map.getCanvas())
    if (location.search.includes('e2e') || location.hash.includes('gallery')) (window as unknown as { __map: MLMap }).__map = map

    const ready = () => {
      addMarkerImages(map)
      apply()
    }
    map.on('style.load', ready)
    map.on('styleimagemissing', () => addMarkerImages(map))
    map.once('load', () => {
      el.current?.querySelector('.maplibregl-ctrl-attrib')?.classList.remove('maplibregl-compact-show')
      el.current?.querySelector('.maplibregl-ctrl-attrib')?.removeAttribute('open')
      propsRef.current.onReady?.()
    })
    let t: number | undefined
    map.on('idle', () => {
      window.clearTimeout(t)
      t = window.setTimeout(notifyBackdrop, 140)
    })
    map.on('rotate', () => propsRef.current.onBearing?.(map.getBearing()))
    map.on('dragstart', (e) => {
      if ((e as { originalEvent?: Event }).originalEvent) propsRef.current.onUserPan?.()
    })

    let consumed: Event | null = null
    map.on('click', (e) => {
      if (propsRef.current.onMapClick?.(e.lngLat.lat, e.lngLat.lng)) consumed = e.originalEvent
    })
    const hit = (e: maplibregl.MapMouseEvent & { features?: maplibregl.MapGeoJSONFeature[] }) => {
      if (e.originalEvent === consumed) return
      const id = e.features?.[0]?.properties?.id as string | undefined
      if (id) propsRef.current.onSelect(id)
    }
    for (const layer of ['place-pin', 'place-pin-minor', 'parking-pin', 'selected-pin', 'room-dot', 'class-pin']) {
      map.on('click', layer, hit)
      map.on('mouseenter', layer, () => (map.getCanvas().style.cursor = 'pointer'))
      map.on('mouseleave', layer, () => (map.getCanvas().style.cursor = ''))
    }
    map.on('click', 'parking-cluster', async (e: maplibregl.MapMouseEvent & { features?: maplibregl.MapGeoJSONFeature[] }) => {
      const f = e.features?.[0]
      if (!f) return
      const src = map.getSource('parking') as GeoJSONSource
      const zoom = await src.getClusterExpansionZoom(f.properties.cluster_id)
      map.easeTo({ center: (f.geometry as GeoJSON.Point).coordinates as [number, number], zoom: zoom + 0.5, duration: prefersReducedMotion() ? 0 : CameraMotion.ease })
    })
    map.on('mouseenter', 'parking-cluster', () => (map.getCanvas().style.cursor = 'pointer'))
    map.on('mouseleave', 'parking-cluster', () => (map.getCanvas().style.cursor = ''))

    return () => {
      setBackdropSource(null)
      map.remove()
      mapRef.current = null
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [])

  useEffect(() => {
    const map = mapRef.current
    if (map && themeApplied.current !== props.theme) {
      themeApplied.current = props.theme
      map.setStyle(buildStyle(props.theme))
    }
  }, [props.theme])

  useEffect(apply, [props.places, props.route, props.endpoints, props.selected, props.you, props.focus, props.classPins, props.buses])

  useImperativeHandle(ref, () => ({
    flyToPlace(p, zoom = 17.2) {
      const map = mapRef.current
      if (!map) return
      const dur = prefersReducedMotion() ? 0 : CameraMotion.fly
      map.flyTo({ center: [p.lon, p.lat], zoom: Math.max(map.getZoom(), zoom), padding: propsRef.current.padding, duration: dur, essential: false, curve: 1.2 })
    },
    flyToLngLat(lng, lat, zoom = 17) {
      mapRef.current?.flyTo({ center: [lng, lat], zoom, padding: propsRef.current.padding, duration: prefersReducedMotion() ? 0 : CameraMotion.fly })
    },
    fitCoords(coords, maxZoom = 18) {
      const map = mapRef.current
      if (!map || !coords.length) return
      const b = new maplibregl.LngLatBounds(coords[0], coords[0])
      coords.forEach((c) => b.extend(c))
      const pad = propsRef.current.padding
      const full = { top: pad.top ?? 0, bottom: pad.bottom ?? 0, left: pad.left ?? 0, right: pad.right ?? 0 }
      // the map keeps the padding of its last move and fitBounds adds its own on top, so measure with the panel's padding alone
      const prev = map.getPadding()
      map.setPadding(full)
      const cam = map.cameraForBounds(b, { padding: 36, maxZoom })
      map.setPadding(prev)
      if (cam) map.flyTo({ ...cam, padding: full, duration: prefersReducedMotion() ? 0 : CameraMotion.fly, essential: false })
    },
    resetNorth() {
      mapRef.current?.easeTo({ bearing: 0, pitch: 0, duration: prefersReducedMotion() ? 0 : CameraMotion.ease })
    },
    zoomBy(d) {
      mapRef.current?.easeTo({ zoom: mapRef.current.getZoom() + d, duration: prefersReducedMotion() ? 0 : 220 })
    },
    getMap: () => mapRef.current,
    follow(lng, lat) {
      const map = mapRef.current
      if (!map) return
      map.easeTo({ center: [lng, lat], zoom: Math.max(map.getZoom(), 16.8), padding: propsRef.current.padding, duration: prefersReducedMotion() ? 0 : 700 })
    },
    setCamera(c) {
      mapRef.current?.jumpTo({ center: [c.lng, c.lat], zoom: c.zoom, bearing: c.bearing ?? 0, pitch: c.pitch ?? 0 })
    },
  }))

  return <div ref={el} className="map-root" role="application" aria-label="Map of the UC Santa Cruz campus" />
})
