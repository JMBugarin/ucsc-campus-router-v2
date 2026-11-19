import type { Place, RoomGuide } from '../src/data/types'

export const ACCESS: string[]
export const SOURCES: string[]
export function metres(a: [number, number], b: [number, number]): number
export function bearing(a: [number, number], b: [number, number]): number
export function compass(deg: number): string
export function floorFromNumber(room: string): string | null
export function floorOf(level: string | null | undefined, room: string, guide?: { floor?: string }): { label: string; basis: 'checked' | 'map+number' | 'map' } | undefined
export function readGuide(key: string, raw: unknown, roomPoint?: [number, number]): { guide?: Partial<RoomGuide> & { floor?: string; entrance?: { lat: number; lon: number; label?: string } }; errors: string[] }
export function buildRooms(input: {
  buildings: unknown[]
  extraAliases?: Record<string, string[]>
  classrooms?: unknown[]
  overrides?: Record<string, unknown>
}): { rooms: Place[]; byBuilding: Record<string, string[]>; errors: string[] }
