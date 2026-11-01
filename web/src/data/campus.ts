import type { GraphFile, Place, PlacesFile } from './types'

const base = import.meta.env.BASE_URL
export async function loadPlaces(): Promise<PlacesFile> {
  const r = await fetch(`${base}data/places.json`)
  if (!r.ok) throw new Error(`places ${r.status}`)
  return r.json()
}
export async function loadGraph(): Promise<GraphFile> {
  const r = await fetch(`${base}data/graph.json`)
  if (!r.ok) throw new Error(`graph ${r.status}`)
  return r.json()
}

export const CAMPUS_CENTER: [number, number] = [-122.0585, 36.9995]
export const CAMPUS_BOUNDS: [[number, number], [number, number]] = [[-122.085, 36.975], [-122.035, 37.012]]

export const SHUTTLES = [
  { name: 'Loop', note: 'Circulator service' },
  { name: 'Upper Campus', note: 'Circulator service' },
  { name: 'Upper Campus Limited', note: 'Circulator service' },
  { name: 'Night Upper Campus', note: 'Circulator service' },
]
export const TRANSIT_LINKS = {
  tapsBuses: 'https://transportation.ucsc.edu/buses-shuttles/index.html',
  metro: 'https://www.scmtd.com/',
}

export function placeLabel(p: Place): string {
  return p.name
}
