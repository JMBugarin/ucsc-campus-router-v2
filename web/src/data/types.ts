import type { Category } from '../design/tokens'

export type LngLat = [number, number]
export interface Place {
  id: string
  name: string
  kind: Category
  lat: number
  lon: number
  aliases: string[]
  subtitle?: string
  entrances?: [number, number][]
  rooms?: number
  source: string
  osm?: string
}
export interface PlacesFile {
  attribution: string
  places: Place[]
}
export interface GraphFile {
  lat: number[]
  lon: number[]
  ele: number[]
  edges: number[]
}
