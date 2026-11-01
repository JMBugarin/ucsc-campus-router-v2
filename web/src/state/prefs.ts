import { useEffect, useState } from 'react'

export type ThemeMode = 'auto' | 'light' | 'dark'

function read<T>(k: string, d: T): T {
  try {
    const v = localStorage.getItem(k)
    return v === null ? d : (JSON.parse(v) as T)
  } catch {
    return d
  }
}
function write(k: string, v: unknown) {
  try {
    localStorage.setItem(k, JSON.stringify(v))
  } catch {
    /* storage may be unavailable */
  }
}

export function usePref<T>(key: string, initial: T): [T, (v: T) => void] {
  const [v, setV] = useState<T>(() => read(key, initial))
  return [v, (n) => (setV(n), write(key, n))]
}

/** Resolves auto/light/dark and mirrors it onto <html> so CSS and the map share one source of truth. */
export function useTheme(): { mode: ThemeMode; setMode: (m: ThemeMode) => void; theme: 'light' | 'dark' } {
  const [mode, setMode] = usePref<ThemeMode>('theme', 'auto')
  const forced = new URLSearchParams(location.search).get('theme') as 'light' | 'dark' | null
  const [sys, setSys] = useState<'light' | 'dark'>(() => (window.matchMedia('(prefers-color-scheme: light)').matches ? 'light' : 'dark'))
  useEffect(() => {
    const mq = window.matchMedia('(prefers-color-scheme: light)')
    const on = () => setSys(mq.matches ? 'light' : 'dark')
    mq.addEventListener('change', on)
    return () => mq.removeEventListener('change', on)
  }, [])
  const theme = forced ?? (mode === 'auto' ? sys : mode)
  useEffect(() => {
    document.documentElement.dataset.theme = theme
    document.documentElement.dataset.resolvedTheme = theme
    document.querySelector('meta[name="theme-color"]')?.setAttribute('content', theme === 'dark' ? '#0b1220' : '#eef0e8')
  }, [theme])
  return { mode, setMode, theme }
}
