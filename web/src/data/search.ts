import type { Place } from './types'

const norm = (s: string) =>
  s
    .toLowerCase()
    .normalize('NFD')
    .replace(/[̀-ͯ]/g, '')
    .replace(/&/g, ' and ')
    .replace(/[^a-z0-9]+/g, ' ')
    .trim()

const SYNONYMS: Record<string, string> = { sci: 'sciences', science: 'sciences', eng: 'engineering', engr: 'engineering', bldg: 'building', lib: 'library', hall: 'hall', coffee: 'cafe', cafes: 'cafe', restaurant: 'dining', food: 'dining', eat: 'dining', lot: 'lot' }

/** Damerau-Levenshtein distance with an early exit. */
export function editDistance(a: string, b: string, max = 2): number {
  if (Math.abs(a.length - b.length) > max) return max + 1
  const m = a.length
  const n = b.length
  let prev2: number[] = []
  let prev = Array.from({ length: n + 1 }, (_, j) => j)
  for (let i = 1; i <= m; i++) {
    const cur = [i]
    let best = i
    for (let j = 1; j <= n; j++) {
      const cost = a[i - 1] === b[j - 1] ? 0 : 1
      let v = Math.min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + cost)
      if (i > 1 && j > 1 && a[i - 1] === b[j - 2] && a[i - 2] === b[j - 1]) v = Math.min(v, prev2[j - 2] + 1)
      cur[j] = v
      best = Math.min(best, v)
    }
    if (best > max) return max + 1
    prev2 = prev
    prev = cur
  }
  return prev[n]
}

interface Entry {
  place: Place
  names: string[]
  words: string[]
  label: string
}

export class SearchIndex {
  private entries: Entry[]
  constructor(places: Place[]) {
    this.entries = places.map((place) => {
      const names = [place.name, ...place.aliases].map(norm).filter(Boolean)
      const label = norm(`${place.name} ${place.kind} ${place.subtitle ?? ''}`)
      const words = [...new Set(names.flatMap((n) => n.split(' ')))]
      return { place, names, words, label }
    })
  }

  search(query: string, limit = 12, kind?: Place['kind']): Place[] {
    const q = norm(query)
    const pool = kind ? this.entries.filter((e) => e.place.kind === kind) : this.entries
    if (!q) return pool.slice(0, limit).map((e) => e.place)
    const qWords = q.split(' ').map((w) => SYNONYMS[w] ?? w)
    const scored: [number, Entry][] = []
    for (const e of pool) {
      const s = this.score(e, q, qWords)
      if (s > 0) scored.push([s, e])
    }
    scored.sort((a, b) => b[0] - a[0] || a[1].place.name.length - b[1].place.name.length)
    return scored.slice(0, limit).map(([, e]) => e.place)
  }

  private score(e: Entry, q: string, qWords: string[]): number {
    let best = 0
    for (const n of e.names) {
      if (n === q) best = Math.max(best, 100)
      else if (n.startsWith(q)) best = Math.max(best, 90 - Math.min(20, n.length - q.length) / 2)
      else if (n.includes(` ${q}`)) best = Math.max(best, 70)
    }
    if (best >= 70) return best
    // every query word must match some word of the name: exact, prefix, or within a typo
    let total = 0
    for (const w of qWords) {
      let wBest = 0
      for (const ew of e.words) {
        if (ew === w) wBest = Math.max(wBest, 10)
        else if (ew.startsWith(w)) wBest = Math.max(wBest, 8)
        else if (w.length >= 4 && editDistance(w, ew.slice(0, w.length + 1), w.length >= 7 ? 2 : 1) <= (w.length >= 7 ? 2 : 1)) wBest = Math.max(wBest, 5)
        else if (w.length >= 3 && e.label.includes(w)) wBest = Math.max(wBest, 3)
      }
      if (!wBest) return best
      total += wBest
    }
    return Math.max(best, 20 + total / qWords.length)
  }
}
