type LatLon = [number, number]
type XY = [number, number]

const KY = 110540
const STRAIGHT = Math.sin((2 * Math.PI) / 180)

function simplify(p: XY[], tol: number): XY[] {
  const keep = new Uint8Array(p.length)
  keep[0] = keep[p.length - 1] = 1
  const stack: [number, number][] = [[0, p.length - 1]]
  while (stack.length) {
    const [s, e] = stack.pop()!
    const [sx, sy] = p[s]
    const dx = p[e][0] - sx
    const dy = p[e][1] - sy
    const len2 = dx * dx + dy * dy
    let max = 0
    let at = -1
    for (let i = s + 1; i < e; i++) {
      const t = len2 ? Math.max(0, Math.min(1, ((p[i][0] - sx) * dx + (p[i][1] - sy) * dy) / len2)) : 0
      const d = Math.hypot(p[i][0] - sx - t * dx, p[i][1] - sy - t * dy)
      if (d > max) {
        max = d
        at = i
      }
    }
    if (max > tol) {
      keep[at] = 1
      stack.push([s, at], [at, e])
    }
  }
  return p.filter((_, i) => keep[i])
}

/**
 * A line as it should look on the map: survey jitter under `tolerance` metres dropped, then every corner
 * turned into a curve that passes within `maxOffset` metres of it. Where two corners share a short side,
 * the sharper one gets more of it. The ends stay exactly where they were.
 */
export function smoothLine(pts: LatLon[], { tolerance = 1, maxOffset = 4, maxCut = 30 } = {}): LatLon[] {
  if (pts.length < 3) return pts.map((p) => [p[0], p[1]])
  const [lat0, lon0] = pts[0]
  const kx = 111320 * Math.cos((lat0 * Math.PI) / 180)
  let xy: XY[] = []
  for (const [la, lo] of pts) {
    const q: XY = [(lo - lon0) * kx, (la - lat0) * KY]
    const last = xy[xy.length - 1]
    if (!last || Math.hypot(q[0] - last[0], q[1] - last[1]) > 0.2) xy.push(q)
  }
  const [la1, lo1] = pts[pts.length - 1]
  const end: XY = [(lo1 - lon0) * kx, (la1 - lat0) * KY]
  if (xy.length > 1) xy[xy.length - 1] = end
  else xy.push(end)
  xy = simplify(xy, tolerance)

  const out: XY[] = [xy[0]]
  const push = (q: XY) => {
    const last = out[out.length - 1]
    if (Math.hypot(q[0] - last[0], q[1] - last[1]) > 0.05) out.push(q)
  }
  const n = xy.length
  const len = xy.slice(1).map((q, j) => Math.hypot(q[0] - xy[j][0], q[1] - xy[j][1]))
  const turn = new Float64Array(n)
  const want = new Float64Array(n)
  const weight = new Float64Array(n)
  for (let i = 1; i < n - 1; i++) {
    if (len[i - 1] < 1e-6 || len[i] < 1e-6) continue
    const dot = ((xy[i - 1][0] - xy[i][0]) * (xy[i + 1][0] - xy[i][0]) + (xy[i - 1][1] - xy[i][1]) * (xy[i + 1][1] - xy[i][1])) / (len[i - 1] * len[i])
    // cosine of half the angle between the two sides: 0 going straight on, 1 doubling back
    const cosHalf = Math.sqrt(Math.max(0, (1 + dot) / 2))
    if (cosHalf < STRAIGHT) continue
    turn[i] = 2 * Math.asin(Math.min(1, cosHalf))
    want[i] = Math.min(maxCut, (2 * maxOffset) / cosHalf)
    weight[i] = Math.min(50, Math.tan(turn[i] / 2) ** 2)
  }
  // each side is shared by the corners at its ends; a short stub stays straight at either end of the line
  const behind = new Float64Array(n)
  const ahead = new Float64Array(n)
  for (let j = 0; j < n - 1; j++) {
    const L = len[j]
    const a = want[j]
    const b = want[j + 1]
    let ga = a
    let gb = b
    if (a + b > L) {
      const share = weight[j] + weight[j + 1] > 0 ? (L * weight[j]) / (weight[j] + weight[j + 1]) : L / 2
      ga = Math.min(a, Math.max(Math.min(a, 0.2 * L), Math.min(share, L - Math.min(b, 0.2 * L))))
      gb = Math.min(b, L - ga)
    }
    ahead[j] = j + 1 === n - 1 ? Math.min(ga, 0.85 * L) : ga
    behind[j + 1] = j === 0 ? Math.min(gb, 0.85 * L) : gb
  }
  for (let i = 1; i < n - 1; i++) {
    const [bx, by] = xy[i]
    if (!turn[i] || !behind[i] || !ahead[i]) {
      push(xy[i])
      continue
    }
    const ux = (xy[i - 1][0] - bx) / len[i - 1]
    const uy = (xy[i - 1][1] - by) / len[i - 1]
    const vx = (xy[i + 1][0] - bx) / len[i]
    const vy = (xy[i + 1][1] - by) / len[i]
    // a quadratic curve from d1 back to d2 ahead, pulled in until it passes within maxOffset of the corner
    const k = Math.min(1, (4 * maxOffset) / Math.max(1e-9, Math.hypot(behind[i] * ux + ahead[i] * vx, behind[i] * uy + ahead[i] * vy)))
    const d1 = behind[i] * k
    const d2 = ahead[i] * k
    const p0: XY = [bx + ux * d1, by + uy * d1]
    const p2: XY = [bx + vx * d2, by + vy * d2]
    const ax = -ux * d1
    const ay = -uy * d1
    const cx = vx * d2
    const cy = vy * d2
    const dir = ax * cy - ay * cx >= 0 ? 1 : -1
    const from = Math.atan2(ay, ax)
    const steps = Math.min(24, Math.max(2, Math.ceil(turn[i] / 0.14)))
    push(p0)
    // sample where the heading has turned by equal steps, so tight and gentle parts look equally smooth
    for (let s = 1; s < steps; s++) {
      const h = from + (dir * turn[i] * s) / steps
      const wx = Math.cos(h)
      const wy = Math.sin(h)
      const ca = ax * wy - ay * wx
      const cc = cx * wy - cy * wx
      const t = Math.abs(ca - cc) > 1e-12 ? Math.max(0, Math.min(1, ca / (ca - cc))) : s / steps
      const m0 = (1 - t) * (1 - t)
      const m1 = 2 * (1 - t) * t
      const m2 = t * t
      push([m0 * p0[0] + m1 * bx + m2 * p2[0], m0 * p0[1] + m1 * by + m2 * p2[1]])
    }
    push(p2)
  }
  const tail = xy[xy.length - 1]
  const prev = out[out.length - 1]
  if (out.length > 1 && Math.hypot(tail[0] - prev[0], tail[1] - prev[1]) <= 0.05) out[out.length - 1] = tail
  else out.push(tail)

  const back = out.map(([x, y]): LatLon => [Math.round((lat0 + y / KY) * 1e7) / 1e7, Math.round((lon0 + x / kx) * 1e7) / 1e7])
  back[0] = [pts[0][0], pts[0][1]]
  back[back.length - 1] = [la1, lo1]
  return back
}

const metres = (a: LatLon, b: LatLon) => Math.hypot((b[0] - a[0]) * KY, (b[1] - a[1]) * 111320 * Math.cos((a[0] * Math.PI) / 180))

export const lineMetres = (pts: LatLon[]) => pts.slice(1).reduce((s, p, i) => s + metres(pts[i], p), 0)

/** The point `d` metres along a line, clamped to its ends. */
export function pointAlong(pts: LatLon[], d: number): LatLon {
  let left = Math.max(0, d)
  for (let i = 1; i < pts.length; i++) {
    const m = metres(pts[i - 1], pts[i])
    if (left <= m && m > 0) {
      const t = left / m
      return [pts[i - 1][0] + (pts[i][0] - pts[i - 1][0]) * t, pts[i - 1][1] + (pts[i][1] - pts[i - 1][1]) * t]
    }
    left -= m
  }
  return pts[pts.length - 1]
}
