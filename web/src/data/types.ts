import type { Category } from '../design/tokens'

export type LngLat = [number, number]
export type Access = 'outside' | 'lobby' | 'library'
export interface RoomDoor {
  lat: number
  lon: number
  meters: number
  /** direction from this door to the room */
  toward: string
  label?: string
  /** someone stood at this door and confirmed it leads to the room */
  checked?: boolean
}
export interface RoomGuide {
  access?: Access
  wing?: string
  note?: string
  steps?: string[]
  stepFree?: boolean
  elevator?: string
  checked: string
  source: 'walk' | 'student-tip'
}
export interface RoomInfo {
  building: string
  number: string
  floor?: { label: string; basis: 'checked' | 'map+number' | 'map' }
  door?: RoomDoor
  guide?: RoomGuide
}
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
  /** classroom place ids in this building, lowest floor first */
  roomIds?: string[]
  room?: RoomInfo
  source: string
  osm?: string
  /** GTFS stop ids served here (METRO) */
  stops?: string[]
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
  /** each edge is listed once and runs both ways */
  undirected?: boolean
  /** bends between joined nodes: pairs (a < b, flat), offsets into pts, and the points (lat, lon flat) from a to b */
  shapes?: { pairs: number[]; off: number[]; pts: number[] }
}
