import type { Map as MLMap } from 'maplibre-gl'
import { ICON_PATHS } from '../design/icons'
import { CATEGORY_COLOR, type Category } from '../design/tokens'

const GLYPH: Record<Category, keyof typeof ICON_PATHS> = {
  academic: 'academic',
  college: 'college',
  library: 'library',
  dining: 'dining',
  landmark: 'landmark',
  transit: 'transit',
  parking: 'parking',
}

/** Round, flat category marker with a white rim: legible on forest, roads and buildings alike. */
export function addMarkerImages(map: MLMap) {
  const px = 2
  const size = 30
  for (const kind of Object.keys(CATEGORY_COLOR) as Category[]) {
    const id = `pin-${kind}`
    if (map.hasImage(id)) continue
    const c = document.createElement('canvas')
    c.width = c.height = size * px
    const ctx = c.getContext('2d')!
    ctx.scale(px, px)
    ctx.shadowColor = 'rgba(0,0,0,0.35)'
    ctx.shadowBlur = 3
    ctx.shadowOffsetY = 1
    ctx.beginPath()
    ctx.arc(size / 2, size / 2, 12, 0, Math.PI * 2)
    ctx.fillStyle = CATEGORY_COLOR[kind]
    ctx.fill()
    ctx.shadowColor = 'transparent'
    ctx.lineWidth = 2
    ctx.strokeStyle = '#ffffff'
    ctx.stroke()
    ctx.save()
    ctx.translate(size / 2 - 8, size / 2 - 8)
    ctx.scale(16 / 24, 16 / 24)
    ctx.strokeStyle = '#ffffff'
    ctx.lineWidth = 2.2
    ctx.lineCap = 'round'
    ctx.lineJoin = 'round'
    // the path strings use implicit "M x y" pairs; Path2D accepts the same grammar as SVG
    ctx.stroke(new Path2D(ICON_PATHS[GLYPH[kind]]))
    ctx.restore()
    map.addImage(id, ctx.getImageData(0, 0, size * px, size * px), { pixelRatio: px })
  }
}
