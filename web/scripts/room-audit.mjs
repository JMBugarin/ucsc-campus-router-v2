// Ranks the classrooms most likely to confuse someone and writes the walking worksheet to
// docs/room-audit.md. Run after npm run data: npm run rooms:audit
import { readFileSync, writeFileSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'
import { compass, bearing, metres } from './rooms.mjs'

const here = dirname(fileURLToPath(import.meta.url))
const root = join(here, '..', '..')
const LIMIT = Number(process.argv[2] ?? 20)
const SITE = 'https://jmbugarin.github.io/ucsc-campus-router-v2/'

// buildings where the outline does not match how you get in: libraries, labs and the engineering complex
const MIXED = new Set(['mchenry-library', 'science-engineering-library', 'baskin-engineering', 'baskin-auditorium', 'engineering-2', 'earth-marine-sciences', 'thimann-labs', 'physical-sciences'])

const places = JSON.parse(readFileSync(join(root, 'web', 'public', 'data', 'places.json'), 'utf8')).places
const buildings = JSON.parse(readFileSync(join(root, 'data', 'buildings.json'), 'utf8')).buildings
const byId = new Map(places.map((p) => [p.id, p]))

function rank(rooms) {
  return rooms
    .map((r) => {
      const b = buildings.find((x) => x.id === r.room.building)
      const doors = (b?.entrances ?? []).filter((e) => e.kind !== 'approach')
      const at = [r.lat, r.lon]
      const main = doors.find((d) => d.kind === 'main') ?? doors[0]
      const mainGap = main ? metres([main.lat, main.lon], at) - (r.room.door?.meters ?? 0) : 0
      const why = []
      let score = 0
      if (MIXED.has(r.room.building)) {
        score += 3
        why.push('mixed-use building')
      }
      if ((r.room.door?.meters ?? 99) >= 25) {
        score += 2
        why.push(`nearest mapped door ${r.room.door?.meters ?? '?'} m away`)
      }
      if (r.room.floor?.basis === 'map') {
        score += 2
        why.push('floor not confirmed by the room number')
      }
      if (r.room.floor && r.room.floor.label !== '1') {
        score += 1
        why.push(`not on floor 1`)
      }
      if (doors.length <= 1) {
        score += 1
        why.push('only one mapped door')
      }
      if (mainGap >= 15) {
        score += 1
        why.push(`main entrance ${Math.round(mainGap)} m farther than the nearest door`)
      }
      return { r, b, doors, score, why }
    })
    .filter((x) => !x.r.room.guide)
    .sort((a, b) => b.score - a.score || a.r.name.localeCompare(b.r.name))
}

const ranked = rank(places.filter((p) => p.kind === 'room')).slice(0, LIMIT)
const lines = [
  '# Room audit',
  '',
  `The ${ranked.length} classrooms most likely to send someone to the wrong side, floor or door, ranked by \`web/scripts/room-audit.mjs\` (regenerate with \`npm run rooms:audit\` in \`web/\`; checked rooms drop off the list).`,
  '',
  'Walk each one from the outside, the way a student would arrive. Open the room on your phone with the link, add `?audit` to fill in the guide on the spot, then paste the copied JSON into `data/rooms.json` and run `npm run data`. Write only what you saw; leave a field out rather than guess. See [room guides](room-guides.md) for what each field means.',
  '',
  '| # | Room | Why it is on the list |',
  '|---|---|---|',
  ...ranked.map((x, i) => `| ${i + 1} | [${x.r.name}](${SITE}#/p/${x.r.id}?audit) | ${x.why.join('; ')} |`),
  '',
]
for (const [i, x] of ranked.entries()) {
  const at = [x.r.lat, x.r.lon]
  const doors = x.doors
    .map((d) => ({ d, m: metres([d.lat, d.lon], at) }))
    .sort((a, b) => a.m - b.m)
    .map(({ d, m }) => `${Math.round(m)} m, room is ${compass(bearing([d.lat, d.lon], at))} of it${d.kind === 'main' ? ' (OSM main entrance)' : ''}`)
  lines.push(
    `## ${i + 1}. ${x.r.name}`,
    '',
    `- Campus map: floor ${x.r.room.floor?.label ?? 'unknown'} (${x.r.room.floor?.basis === 'map+number' ? 'matches the room number' : 'does not match the room number'}).`,
    `- Mapped doors, nearest first: ${doors.join('; ') || 'none'}.`,
    `- Other rooms here: ${(byId.get(x.r.room.building)?.roomIds ?? []).filter((id) => id !== x.r.id).map((id) => byId.get(id)?.room?.number).join(', ') || 'none'}.`,
    '- To record: how you get in (outside, lobby or library), the door you would use and where it is, the floor as signed, wing or side, one line that would have saved you a minute, up to five short steps from the door, step-free or not, elevator.',
    '',
  )
}
writeFileSync(join(root, 'docs', 'room-audit.md'), lines.join('\n'))
console.log(`room audit: ${ranked.length} rooms written to docs/room-audit.md`)
