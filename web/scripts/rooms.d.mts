import type { Place, RoomFloor, RoomGuide } from '../src/data/types'

export interface FloorsFile {
  sources: Record<string, { name: string; url: string; read?: string; says?: string }>
  rooms: Record<string, { floor: string; where?: RoomFloor['where']; source: string }>
}

export const ACCESS: string[]
export const SOURCES: string[]
export const WHERE: string[]
export function metres(a: [number, number], b: [number, number]): number
export function bearing(a: [number, number], b: [number, number]): number
export function compass(deg: number): string
export function floorOf(key: string, guide: { floor?: string } | undefined, floors: FloorsFile | Record<string, unknown>): RoomFloor | undefined
export function checkFloors(floors: unknown, exists: (key: string) => boolean): string[]
export function readGuide(key: string, raw: unknown, roomPoint?: [number, number]): { guide?: Partial<RoomGuide> & { floor?: string; entrance?: { lat: number; lon: number; label?: string } }; errors: string[] }
export function buildRooms(input: {
  buildings: unknown[]
  extraAliases?: Record<string, string[]>
  classrooms?: unknown[]
  overrides?: Record<string, unknown>
  floors?: FloorsFile | Record<string, unknown>
}): { rooms: Place[]; byBuilding: Record<string, string[]>; errors: string[] }
