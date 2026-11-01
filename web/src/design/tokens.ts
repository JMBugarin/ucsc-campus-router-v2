/** TypeScript mirror of tokens.css for code that cannot read CSS variables (map camera, canvas). */
export const Space = { xs: 4, s: 8, m: 12, l: 16, xl: 20, xxl: 24 } as const
export const Radius = { control: 10, card: 12, sheet: 18, panel: 20 } as const
export const Motion = { fast: 120, base: 180, slow: 280 } as const
/** Map camera moves are allowed to run longer than UI transitions to stay geographically legible. */
export const CameraMotion = { fly: 900, ease: 450 } as const

export const CATEGORY_COLOR = {
  academic: '#3a78c8',
  college: '#2e8f6b',
  library: '#8a5bc4',
  dining: '#d1782a',
  landmark: '#c2923a',
  transit: '#2a8fa8',
  parking: '#6f7d92',
} as const
export type Category = keyof typeof CATEGORY_COLOR

export const CATEGORY_LABEL: Record<Category, string> = {
  academic: 'Academic',
  college: 'Colleges',
  library: 'Libraries',
  dining: 'Dining',
  landmark: 'Landmarks',
  transit: 'Transit',
  parking: 'Parking',
}

export const MOBILE_QUERY = '(max-width: 720px)'
