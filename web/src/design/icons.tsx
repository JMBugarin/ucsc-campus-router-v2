import type { SVGProps } from 'react'

/** 24x24 stroke icons. Path data is shared with the map's canvas markers. */
export const ICON_PATHS = {
  search: 'M11 4a7 7 0 1 0 0 14 7 7 0 0 0 0-14zM21 21l-4.5-4.5',
  close: 'M6 6l12 12M18 6L6 18',
  back: 'M15 5l-7 7 7 7',
  academic: 'M3 9.5L12 5l9 4.5-9 4.5L3 9.5zM7 12v4.5c0 1 2.2 2.5 5 2.5s5-1.5 5-2.5V12M21 9.5v5',
  college: 'M4 20V9l8-5 8 5v11M9 20v-6h6v6M2 20h20',
  library: 'M5 4h4v16H5zM11 4h4v16h-4zM17.5 5.5l3 .8-3.6 13.4-3-.8',
  dining: 'M7 3v7a2 2 0 0 0 2 2v9M11 3v7a2 2 0 0 1-2 2M17 21V3c-2 1.5-3 4-3 7v3h3',
  parking: 'M5 3h14v18H5zM9.5 17V7.5h3.2a2.7 2.7 0 0 1 0 5.4H9.5',
  transit: 'M6 3h12a2 2 0 0 1 2 2v10a3 3 0 0 1-3 3H7a3 3 0 0 1-3-3V5a2 2 0 0 1 2-2zM4 11h16M8 21v-3M16 21v-3M8 15h.01M16 15h.01',
  landmark: 'M12 3l2.7 5.6 6.1.9-4.4 4.3 1 6.1L12 17l-5.4 2.9 1-6.1-4.4-4.3 6.1-.9L12 3z',
  walk: 'M13 4.5a1.5 1.5 0 1 0 0 .01M10 21l1.5-6-2-2 1-5.5M11.5 8.5l3 2.5 2.5.5M11.5 15l3 2 .5 4',
  route: 'M6 19a2 2 0 1 0 0-.01M18 5a2 2 0 1 0 0-.01M8 19h6a3.5 3.5 0 0 0 0-7h-4a3.5 3.5 0 0 1 0-7h6',
  pin: 'M12 21s7-6.2 7-11.5A7 7 0 0 0 5 9.5C5 14.8 12 21 12 21zM12 7.5a2.2 2.2 0 1 0 0 4.4 2.2 2.2 0 0 0 0-4.4z',
  locate: 'M12 8a4 4 0 1 0 0 8 4 4 0 0 0 0-8zM12 2v3M12 19v3M2 12h3M19 12h3',
  swap: 'M7 4v14M7 18l-3-3M7 18l3-3M17 20V6M17 6l-3 3M17 6l3 3',
  share: 'M12 15V4M8 8l4-4 4 4M5 13v6a1 1 0 0 0 1 1h12a1 1 0 0 0 1-1v-6',
  moon: 'M20 14.5A8 8 0 0 1 9.5 4 8 8 0 1 0 20 14.5z',
  sun: 'M12 8a4 4 0 1 0 0 8 4 4 0 0 0 0-8zM12 2v2M12 20v2M4.9 4.9l1.4 1.4M17.7 17.7l1.4 1.4M2 12h2M20 12h2M4.9 19.1l1.4-1.4M17.7 6.3l1.4-1.4',
  info: 'M12 3a9 9 0 1 0 0 18 9 9 0 0 0 0-18zM12 11v5M12 8h.01',
  warn: 'M12 3.5L2.5 20h19L12 3.5zM12 10v4.5M12 17.5h.01',
  check: 'M5 12.5l4.5 4.5L19 7.5',
  stairs: 'M3 20h5v-4h4v-4h4V8h5',
  bridge: 'M2 17h20M5 17V9M19 17V9M5 9c3 5 11 5 14 0',
  layers: 'M12 3l9 5-9 5-9-5 9-5zM3 13l9 5 9-5',
  bike: 'M6 18a3.5 3.5 0 1 0 0-.01M18 18a3.5 3.5 0 1 0 0-.01M6 18l4-8h5l3 8M10 10l-1-3H7',
  chevron: 'M9 6l6 6-6 6',
  compass: 'M12 3a9 9 0 1 0 0 18 9 9 0 0 0 0-18zM15.5 8.5l-2 5-5 2 2-5 5-2z',
  external: 'M14 4h6v6M20 4l-9 9M18 14v5a1 1 0 0 1-1 1H5a1 1 0 0 1-1-1V7a1 1 0 0 1 1-1h5',
  plus: 'M12 5v14M5 12h14',
  minus: 'M5 12h14',
  empty: 'M4 7l8-4 8 4v10l-8 4-8-4V7zM4 7l8 4 8-4M12 11v10',
} as const

export type IconName = keyof typeof ICON_PATHS

export function Icon({ name, size = 18, ...rest }: { name: IconName; size?: number } & Omit<SVGProps<SVGSVGElement>, 'name'>) {
  return (
    <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={1.8} strokeLinecap="round" strokeLinejoin="round" aria-hidden="true" {...rest}>
      <path d={ICON_PATHS[name]} />
    </svg>
  )
}
