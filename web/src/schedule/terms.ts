export interface Term {
  name: string
  start: string
  end: string
  holidays: string[]
}

export function termsFromJson(json: { terms?: Partial<Term>[] }): Term[] {
  return (json.terms ?? [])
    .map((t) => ({ name: t.name ?? '', start: t.start!, end: t.end!, holidays: t.holidays ?? [] }))
    .sort((a, b) => a.start.localeCompare(b.start))
}

/** The term holding `iso`, else the next to start, else the last. */
export function termFor(terms: Term[], iso: string): Term | null {
  if (!terms.length) return null
  return terms.find((t) => t.start <= iso && iso <= t.end) ?? terms.find((t) => t.start > iso) ?? terms[terms.length - 1]
}

export const holidaysOf = (terms: Term[]) => new Set(terms.flatMap((t) => t.holidays))
