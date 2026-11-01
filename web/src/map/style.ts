import type { StyleSpecification, LayerSpecification, ExpressionSpecification } from 'maplibre-gl'

export type Theme = 'light' | 'dark'

interface Palette {
  land: string
  wood: string
  grass: string
  park: string
  rock: string
  water: string
  waterLine: string
  bldg: string
  bldgLine: string
  campus: string
  roadCasing: string
  road: string
  main: string
  mainCasing: string
  path: string
  steps: string
  text: string
  halo: string
  muted: string
  hillShadow: string
  hillHigh: string
  accent: string
  warn: string
  routeCasing: string
}

const LIGHT: Palette = {
  land: '#eef0e8',
  wood: '#a9c993',
  grass: '#d6e6bf',
  park: '#cfe4b8',
  rock: '#dcd8cd',
  water: '#a6cbe6',
  waterLine: '#8bb8da',
  bldg: '#e4dccd',
  bldgLine: '#bfb39d',
  campus: '#f2f0e6',
  roadCasing: '#cdc8bb',
  road: '#ffffff',
  main: '#fbe3a8',
  mainCasing: '#d9bd72',
  path: '#a77a52',
  steps: '#8a5a3b',
  text: '#26323f',
  halo: 'rgba(255,255,255,0.9)',
  muted: '#5d6b7a',
  hillShadow: '#4c5e48',
  hillHigh: '#ffffff',
  accent: '#0b6fe0',
  warn: '#d9730d',
  routeCasing: '#ffffff',
}
const DARK: Palette = {
  land: '#17202a',
  wood: '#1d4531',
  grass: '#24402f',
  park: '#1b3125',
  rock: '#242b33',
  water: '#10283c',
  waterLine: '#1a3c58',
  bldg: '#374454',
  bldgLine: '#566883',
  campus: '#18202a',
  roadCasing: '#10151b',
  road: '#38424f',
  main: '#6a5a34',
  mainCasing: '#2a2412',
  path: '#c49a6c',
  steps: '#e0a979',
  text: '#dfe7f1',
  halo: 'rgba(12,18,26,0.9)',
  muted: '#93a1b3',
  hillShadow: '#000000',
  hillHigh: '#52667a',
  accent: '#5ac8fa',
  warn: '#ffb454',
  routeCasing: '#0b1118',
}

export const palette = (t: Theme) => (t === 'dark' ? DARK : LIGHT)

const F_REG = ['Noto Sans Regular']
const F_BOLD = ['Noto Sans Bold']

const w = (stops: [number, number][]): ExpressionSpecification => ['interpolate', ['exponential', 1.5], ['zoom'], ...stops.flat()] as ExpressionSpecification

export function buildStyle(theme: Theme): StyleSpecification {
  const c = palette(theme)
  const dark = theme === 'dark'
  const road = ['in', ['get', 'class'], ['literal', ['minor', 'service', 'track']]] as ExpressionSpecification
  const layers: LayerSpecification[] = [
    { id: 'background', type: 'background', paint: { 'background-color': c.land } },
    {
      id: 'landuse-campus',
      type: 'fill',
      source: 'ofm',
      'source-layer': 'landuse',
      filter: ['in', ['get', 'class'], ['literal', ['university', 'school', 'college', 'residential', 'pitch', 'playground', 'cemetery']]],
      paint: { 'fill-color': c.campus, 'fill-opacity': 0.9 },
    },
    {
      id: 'landcover-grass',
      type: 'fill',
      source: 'ofm',
      'source-layer': 'landcover',
      filter: ['in', ['get', 'class'], ['literal', ['grass', 'farmland']]],
      paint: { 'fill-color': c.grass },
    },
    { id: 'landcover-rock', type: 'fill', source: 'ofm', 'source-layer': 'landcover', filter: ['==', ['get', 'class'], 'rock'], paint: { 'fill-color': c.rock } },
    { id: 'landcover-wood', type: 'fill', source: 'ofm', 'source-layer': 'landcover', filter: ['==', ['get', 'class'], 'wood'], paint: { 'fill-color': c.wood, 'fill-opacity': 0.95 } },
    { id: 'park', type: 'fill', source: 'ofm', 'source-layer': 'park', paint: { 'fill-color': c.park, 'fill-opacity': 0.7 } },
    {
      id: 'hillshade',
      type: 'hillshade',
      source: 'dem',
      paint: {
        'hillshade-exaggeration': dark ? 0.55 : 0.45,
        'hillshade-shadow-color': c.hillShadow,
        'hillshade-highlight-color': c.hillHigh,
        'hillshade-accent-color': c.hillShadow,
        'hillshade-illumination-direction': 315,
      },
    },
    { id: 'water', type: 'fill', source: 'ofm', 'source-layer': 'water', paint: { 'fill-color': c.water } },
    { id: 'waterway', type: 'line', source: 'ofm', 'source-layer': 'waterway', paint: { 'line-color': c.waterLine, 'line-width': w([[12, 0.6], [17, 3]]) } },
    {
      id: 'building',
      type: 'fill',
      source: 'ofm',
      'source-layer': 'building',
      minzoom: 14.5,
      paint: { 'fill-color': c.bldg, 'fill-opacity': ['interpolate', ['linear'], ['zoom'], 14.5, 0, 15.5, 1] },
    },
    {
      id: 'building-line',
      type: 'line',
      source: 'ofm',
      'source-layer': 'building',
      minzoom: 16,
      paint: { 'line-color': c.bldgLine, 'line-width': w([[16, 0.5], [19, 1.2]]) },
    },
    // roads: casings first, fills on top
    {
      id: 'road-casing',
      type: 'line',
      source: 'ofm',
      'source-layer': 'transportation',
      minzoom: 13,
      filter: ['all', ['!=', ['get', 'brunnel'], 'tunnel'], ['in', ['get', 'class'], ['literal', ['minor', 'service', 'tertiary', 'secondary', 'primary', 'trunk', 'motorway']]]],
      layout: { 'line-cap': 'round', 'line-join': 'round' },
      paint: { 'line-color': ['case', ['in', ['get', 'class'], ['literal', ['secondary', 'primary', 'trunk', 'tertiary']]], c.mainCasing, c.roadCasing], 'line-width': w([[13, 1], [16, 6], [19, 18]]) },
    },
    {
      id: 'road',
      type: 'line',
      source: 'ofm',
      'source-layer': 'transportation',
      minzoom: 13,
      filter: ['all', ['!=', ['get', 'brunnel'], 'tunnel'], ['in', ['get', 'class'], ['literal', ['minor', 'service', 'tertiary', 'secondary', 'primary', 'trunk', 'motorway']]]],
      layout: { 'line-cap': 'round', 'line-join': 'round' },
      paint: { 'line-color': ['case', ['in', ['get', 'class'], ['literal', ['secondary', 'primary', 'trunk', 'tertiary']]], c.main, c.road], 'line-width': w([[13, 0.6], [16, 4], [19, 14]]) },
    },
    {
      id: 'pedestrian-area',
      type: 'fill',
      source: 'ofm',
      'source-layer': 'transportation',
      filter: ['all', ['==', ['geometry-type'], 'Polygon'], ['==', ['get', 'class'], 'pedestrian']],
      paint: { 'fill-color': dark ? '#323c49' : '#f7f4ea' },
    },
    {
      id: 'path',
      type: 'line',
      source: 'ofm',
      'source-layer': 'transportation',
      minzoom: 14.5,
      filter: ['all', ['==', ['geometry-type'], 'LineString'], ['in', ['get', 'class'], ['literal', ['path', 'pedestrian']]], ['!=', ['get', 'subclass'], 'steps']],
      layout: { 'line-cap': 'round', 'line-join': 'round' },
      paint: { 'line-color': c.path, 'line-opacity': ['interpolate', ['linear'], ['zoom'], 15, 0, 16.5, 0.8], 'line-width': w([[15, 0.5], [17, 1.3], [19, 3.2]]), 'line-dasharray': [2, 1.6] },
    },
    {
      id: 'steps',
      type: 'line',
      source: 'ofm',
      'source-layer': 'transportation',
      minzoom: 16,
      filter: ['all', ['==', ['get', 'subclass'], 'steps']],
      paint: { 'line-color': c.steps, 'line-width': w([[16, 2.5], [19, 6]]), 'line-dasharray': [0.25, 0.6] },
    },
    {
      id: 'bridge',
      type: 'line',
      source: 'ofm',
      'source-layer': 'transportation',
      minzoom: 15,
      filter: ['all', ['==', ['get', 'brunnel'], 'bridge'], ['in', ['get', 'class'], ['literal', ['path', 'pedestrian', 'minor', 'service']]]],
      paint: { 'line-color': dark ? '#9fb2c8' : '#ffffff', 'line-width': w([[15, 1], [19, 5]]), 'line-opacity': 0.9 },
    },
    // labels
    {
      id: 'road-label',
      type: 'symbol',
      source: 'ofm',
      'source-layer': 'transportation_name',
      minzoom: 15.5,
      filter: road,
      layout: { 'symbol-placement': 'line', 'text-field': ['coalesce', ['get', 'name:en'], ['get', 'name']], 'text-font': F_REG, 'text-size': 11 },
      paint: { 'text-color': c.muted, 'text-halo-color': c.halo, 'text-halo-width': 1.4 },
    },
    {
      id: 'water-label',
      type: 'symbol',
      source: 'ofm',
      'source-layer': 'water_name',
      layout: { 'text-field': ['coalesce', ['get', 'name:en'], ['get', 'name']], 'text-font': F_REG, 'text-size': 12 },
      paint: { 'text-color': dark ? '#5f9ac8' : '#4a7fae', 'text-halo-color': c.halo, 'text-halo-width': 1.2 },
    },
    {
      id: 'place-label',
      type: 'symbol',
      source: 'ofm',
      'source-layer': 'place',
      maxzoom: 15,
      filter: ['in', ['get', 'class'], ['literal', ['city', 'town', 'village', 'suburb', 'neighbourhood', 'hamlet']]],
      layout: { 'text-field': ['coalesce', ['get', 'name:en'], ['get', 'name']], 'text-font': F_BOLD, 'text-size': w([[8, 11], [13, 15]]), 'text-transform': 'uppercase', 'text-letter-spacing': 0.08 },
      paint: { 'text-color': c.muted, 'text-halo-color': c.halo, 'text-halo-width': 1.5 },
    },
    // route (drawn under campus markers)
    { id: 'route-casing', type: 'line', source: 'route', filter: ['!=', ['get', 'kind'], 'connector'], layout: { 'line-cap': 'round', 'line-join': 'round' }, paint: { 'line-color': c.routeCasing, 'line-width': w([[14, 6], [17, 10], [19, 16]]), 'line-opacity': 0.92 } },
    { id: 'route-road', type: 'line', source: 'route', filter: ['==', ['get', 'kind'], 2], layout: { 'line-cap': 'round', 'line-join': 'round' }, paint: { 'line-color': c.accent, 'line-opacity': 0.62, 'line-width': w([[14, 3], [17, 6], [19, 10]]) } },
    { id: 'route-path', type: 'line', source: 'route', filter: ['in', ['get', 'kind'], ['literal', [0, 3]]], layout: { 'line-cap': 'round', 'line-join': 'round' }, paint: { 'line-color': c.accent, 'line-width': w([[14, 3.5], [17, 6.5], [19, 11]]) } },
    { id: 'route-bridge', type: 'line', source: 'route', filter: ['==', ['get', 'kind'], 3], layout: { 'line-cap': 'butt' }, paint: { 'line-color': '#ffffff', 'line-width': w([[14, 1], [19, 3.5]]), 'line-dasharray': [1, 1] } },
    { id: 'route-steps', type: 'line', source: 'route', filter: ['==', ['get', 'kind'], 1], layout: { 'line-cap': 'butt', 'line-join': 'round' }, paint: { 'line-color': c.warn, 'line-width': w([[14, 3.5], [17, 6.5], [19, 11]]), 'line-dasharray': [0.45, 0.55] } },
    { id: 'route-connector', type: 'line', source: 'route', filter: ['==', ['get', 'kind'], 'connector'], layout: { 'line-cap': 'round' }, paint: { 'line-color': c.accent, 'line-width': 2.5, 'line-dasharray': [0.1, 2] } },
    // parking clusters and lots
    { id: 'parking-cluster', type: 'circle', source: 'parking', minzoom: 15, filter: ['has', 'point_count'], paint: { 'circle-radius': ['step', ['get', 'point_count'], 15, 6, 18, 20, 22], 'circle-color': '#6f7d92', 'circle-stroke-color': '#ffffff', 'circle-stroke-width': 2, 'circle-opacity': 0.92 } },
    { id: 'parking-cluster-count', type: 'symbol', source: 'parking', minzoom: 15, filter: ['has', 'point_count'], layout: { 'text-field': ['get', 'point_count_abbreviated'], 'text-font': F_BOLD, 'text-size': 12, 'text-allow-overlap': true }, paint: { 'text-color': '#ffffff' } },
    {
      id: 'parking-pin',
      type: 'symbol',
      source: 'parking',
      minzoom: 15,
      filter: ['!', ['has', 'point_count']],
      layout: { 'icon-image': 'pin-parking', 'icon-size': 0.9, 'text-field': ['get', 'name'], 'text-font': F_BOLD, 'text-size': 11, 'text-offset': [0, 1.3], 'text-anchor': 'top', 'text-optional': true, 'icon-padding': 3 },
      paint: { 'text-color': c.text, 'text-halo-color': c.halo, 'text-halo-width': 1.5 },
    },
    // campus places
    {
      id: 'place-pin',
      filter: ['in', ['get', 'kind'], ['literal', ['college', 'library']]],
      type: 'symbol',
      source: 'places',
      layout: {
        'icon-image': ['concat', 'pin-', ['get', 'kind']],
        'icon-size': ['interpolate', ['linear'], ['zoom'], 14, 0.78, 18, 1],
        'icon-padding': 4,
        'symbol-sort-key': ['get', 'rank'],
        'text-field': ['step', ['zoom'], '', 15.2, ['get', 'name']],
        'text-font': F_BOLD,
        'text-size': ['interpolate', ['linear'], ['zoom'], 15, 11, 18, 13],
        'text-offset': [0, 1.35],
        'text-anchor': 'top',
        'text-optional': true,
        'text-max-width': 8,
      },
      paint: { 'text-color': c.text, 'text-halo-color': c.halo, 'text-halo-width': 1.6 },
    },
    {
      id: 'place-pin-minor',
      minzoom: 15.8,
      filter: ['!', ['in', ['get', 'kind'], ['literal', ['college', 'library']]]],
      type: 'symbol',
      source: 'places',
      layout: {
        'icon-image': ['concat', 'pin-', ['get', 'kind']],
        'icon-size': ['interpolate', ['linear'], ['zoom'], 14, 0.78, 18, 1],
        'icon-padding': 4,
        'symbol-sort-key': ['get', 'rank'],
        'text-field': ['step', ['zoom'], '', 15.2, ['get', 'name']],
        'text-font': F_BOLD,
        'text-size': ['interpolate', ['linear'], ['zoom'], 15, 11, 18, 13],
        'text-offset': [0, 1.35],
        'text-anchor': 'top',
        'text-optional': true,
        'text-max-width': 8,
      },
      paint: { 'text-color': c.text, 'text-halo-color': c.halo, 'text-halo-width': 1.6 },
    },
    {
      id: 'selected-ring',
      type: 'circle',
      source: 'selected',
      paint: { 'circle-radius': 22, 'circle-color': c.accent, 'circle-opacity': 0.18, 'circle-stroke-color': c.accent, 'circle-stroke-width': 2 },
    },
    {
      id: 'selected-pin',
      type: 'symbol',
      source: 'selected',
      layout: { 'icon-image': ['concat', 'pin-', ['get', 'kind']], 'icon-size': 1.15, 'icon-allow-overlap': true, 'text-field': ['get', 'name'], 'text-font': F_BOLD, 'text-size': 13, 'text-offset': [0, 1.7], 'text-anchor': 'top', 'text-max-width': 9, 'text-allow-overlap': true },
      paint: { 'text-color': c.text, 'text-halo-color': c.halo, 'text-halo-width': 2 },
    },
    { id: 'endpoint-from', type: 'circle', source: 'endpoints', filter: ['==', ['get', 'role'], 'from'], paint: { 'circle-radius': 7, 'circle-color': '#ffffff', 'circle-stroke-color': c.accent, 'circle-stroke-width': 4 } },
    { id: 'endpoint-to', type: 'circle', source: 'endpoints', filter: ['==', ['get', 'role'], 'to'], paint: { 'circle-radius': 8, 'circle-color': c.accent, 'circle-stroke-color': '#ffffff', 'circle-stroke-width': 3 } },
    { id: 'you-halo', type: 'circle', source: 'you', paint: { 'circle-radius': ['get', 'accuracy_px'], 'circle-color': '#0a84ff', 'circle-opacity': 0.14 } },
    { id: 'you', type: 'circle', source: 'you', paint: { 'circle-radius': 8, 'circle-color': '#0a84ff', 'circle-stroke-color': '#ffffff', 'circle-stroke-width': 3 } },
  ]

  const empty = { type: 'geojson' as const, data: { type: 'FeatureCollection' as const, features: [] } }
  return {
    version: 8,
    glyphs: 'https://tiles.openfreemap.org/fonts/{fontstack}/{range}.pbf',
    sources: {
      ofm: { type: 'vector', url: 'https://tiles.openfreemap.org/planet', attribution: '<a href="https://openfreemap.org" target="_blank" rel="noopener">OpenFreeMap</a> © <a href="https://openmaptiles.org/" target="_blank" rel="noopener">OpenMapTiles</a> data from <a href="https://www.openstreetmap.org/copyright" target="_blank" rel="noopener">OpenStreetMap</a>' },
      dem: { type: 'raster-dem', tiles: ['https://s3.amazonaws.com/elevation-tiles-prod/terrarium/{z}/{x}/{y}.png'], tileSize: 256, maxzoom: 14, encoding: 'terrarium', attribution: 'Terrain: <a href="https://registry.opendata.aws/terrain-tiles/" target="_blank" rel="noopener">Mapzen/AWS Terrain Tiles</a>' },
      places: empty,
      parking: { ...empty, cluster: true, clusterRadius: 44, clusterMaxZoom: 16 },
      route: empty,
      selected: empty,
      endpoints: empty,
      you: empty,
    },
    layers,
  }
}
