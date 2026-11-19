/** Getting the device's position, and when that fails, saying which setting is in the way on this device. */

export type Platform = 'ios' | 'android' | 'mac' | 'windows' | 'other'
export type Browser = 'safari' | 'chrome' | 'firefox' | 'edge' | 'samsung' | 'other'
export interface Env {
  platform: Platform
  browser: Browser
  /** the app this page is open inside (an in-app browser), if any */
  inApp: string | null
}

export function environment(ua: string, touchPoints = 0): Env {
  const ios = /iPhone|iPad|iPod/.test(ua) || (/Macintosh/.test(ua) && touchPoints > 1)
  const platform: Platform = ios ? 'ios' : /Android/.test(ua) ? 'android' : /Macintosh|Mac OS X/.test(ua) ? 'mac' : /Windows/.test(ua) ? 'windows' : 'other'
  const browser: Browser = /Edg(e|A|iOS)?\//.test(ua)
    ? 'edge'
    : /SamsungBrowser/.test(ua)
      ? 'samsung'
      : /Firefox|FxiOS/.test(ua)
        ? 'firefox'
        : /Chrome|CriOS/.test(ua)
          ? 'chrome'
          : /Safari/.test(ua)
            ? 'safari'
            : 'other'
  const apps: [RegExp, string][] = [
    [/Instagram/, 'Instagram'],
    [/FBAN|FBAV|FB_IAB/, 'Facebook'],
    [/Discord/i, 'Discord'],
    [/Snapchat/, 'Snapchat'],
    [/LinkedInApp/, 'LinkedIn'],
    [/musical_ly|TikTok|BytedanceWebview/, 'TikTok'],
    [/Line\//, 'LINE'],
    [/GSA\//, 'the Google app'],
  ]
  let inApp = apps.find(([re]) => re.test(ua))?.[1] ?? null
  // an Android web view, or an iPhone page with no browser name: some app's built-in browser
  if (!inApp && platform === 'android' && /; wv\)/.test(ua)) inApp = 'another app'
  if (!inApp && platform === 'ios' && !/Safari\//.test(ua) && !/CriOS|FxiOS|EdgiOS/.test(ua)) inApp = 'another app'
  return { platform, browser, inApp }
}

export type Failure = 'unsupported' | 'in-app' | 'blocked-system' | 'blocked-site' | 'blocked' | 'unavailable' | 'timeout'

/** Why getting the position failed: `permission` is what the Permissions API says about this site, when it says. */
export function classify(code: number, permission: PermissionState | 'unknown', env: Env): Failure {
  if (code === 1) {
    if (env.inApp) return 'in-app'
    // the site is allowed but the browser still got no position: the operating system is refusing the browser
    if (permission === 'granted') return 'blocked-system'
    if (permission === 'denied') return 'blocked-site'
    return 'blocked'
  }
  return code === 3 ? 'timeout' : 'unavailable'
}

const BROWSER_NAME: Record<Browser, string> = { safari: 'Safari', chrome: 'Chrome', firefox: 'Firefox', edge: 'Edge', samsung: 'Samsung Internet', other: 'your browser' }

const MAC_APP: Record<Browser, string> = { safari: 'Safari', chrome: 'Google Chrome', firefox: 'Firefox', edge: 'Microsoft Edge', samsung: 'your browser', other: 'your browser' }

function systemSteps(env: Env): string[] {
  const b = BROWSER_NAME[env.browser]
  switch (env.platform) {
    case 'mac':
      return ['Open System Settings → Privacy & Security → Location Services.', `Turn Location Services on, then switch on ${MAC_APP[env.browser]} in the list.`]
    case 'ios':
      return ['Open Settings → Privacy & Security → Location Services and turn it on.', env.browser === 'safari' || env.browser === 'other' ? 'In that list, tap Safari Websites and choose While Using the App.' : `In that list, tap ${b} and choose While Using the App.`]
    case 'android':
      return ['Turn on Location from the quick settings at the top of the screen.', `Settings → Apps → ${b} → Permissions → Location → Allow.`]
    case 'windows':
      return ['Open Settings → Privacy & security → Location.', 'Turn on Location services and "Let desktop apps access your location".']
    default:
      return ["Turn on location in your device's settings, and allow your browser to use it."]
  }
}

function siteSteps(env: Env): string[] {
  if (env.platform === 'ios') return env.browser === 'safari' || env.browser === 'other' ? ['In Safari, tap the page menu (aA) next to the address → Website Settings → Location → Allow.'] : [`In ${BROWSER_NAME[env.browser]}'s settings, allow location for this site.`]
  if (env.browser === 'safari') return ['Safari → Settings → Websites → Location: set jmbugarin.github.io to Allow.']
  if (env.browser === 'firefox') return ['Click the icon left of the address and clear the blocked "Access your location" permission.']
  return ['Click or tap the icon left of the address → Location → Allow (in Site settings if it is not listed).']
}

export interface Help {
  title: string
  body: string
  steps: string[]
}

/** What to tell someone whose location didn't come through, for their device and browser. */
export function help(failure: Failure, env: Env): Help {
  const b = BROWSER_NAME[env.browser]
  const again = 'Then come back and press Try again (reload the page if it still says no).'
  switch (failure) {
    case 'unsupported':
      return { title: "This browser can't share its location", body: 'Pick your starting point on the map or search an address instead.', steps: [] }
    case 'in-app':
      return { title: `Open this page in ${env.platform === 'ios' ? 'Safari' : 'Chrome'}`, body: `It's open inside ${env.inApp}, which doesn't give web pages your location.`, steps: [`Use ${env.inApp}'s menu (••• or the share icon) → Open in browser.`] }
    case 'blocked-system':
      return { title: `Location is off for ${b} on this ${env.platform === 'mac' ? 'Mac' : 'device'}`, body: `This site is allowed, but your ${env.platform === 'ios' ? 'iPhone' : env.platform === 'mac' ? 'Mac' : 'device'} isn't letting ${b} use location.`, steps: [...systemSteps(env), again] }
    case 'blocked-site':
      return { title: 'Location is blocked for this site', body: `${b} is set to block location here.`, steps: [...siteSteps(env), again] }
    case 'blocked':
      return { title: 'Location is turned off', body: `Either your ${env.platform === 'ios' ? 'iPhone' : env.platform === 'mac' ? 'Mac' : 'device'} or ${b} is blocking it. Check both:`, steps: [...systemSteps(env), ...siteSteps(env), again] }
    case 'timeout':
      return { title: 'Finding your location took too long', body: 'Your device answered too slowly.', steps: ['Turn on Wi-Fi (it helps even when not connected) and try again.'] }
    default:
      return { title: "Your location couldn't be found", body: 'Location is allowed, but your device had no fix.', steps: ['Turn on Wi-Fi, or step outside or near a window, and try again.'] }
  }
}

const once = (opts: PositionOptions) => new Promise<GeolocationPosition>((ok, fail) => navigator.geolocation.getCurrentPosition(ok, fail, opts))

/** The position, retrying without high accuracy when the precise fix times out or isn't available (common on Macs). */
export async function getPosition(): Promise<{ pos: GeolocationPosition } | { failure: Failure; help: Help }> {
  const env = environment(navigator.userAgent, navigator.maxTouchPoints ?? 0)
  if (!('geolocation' in navigator)) return { failure: 'unsupported', help: help('unsupported', env) }
  let error: GeolocationPositionError | null = null
  for (const opts of [
    { enableHighAccuracy: true, timeout: 10_000, maximumAge: 30_000 },
    { enableHighAccuracy: false, timeout: 15_000, maximumAge: 120_000 },
  ]) {
    try {
      return { pos: await once(opts) }
    } catch (e) {
      error = e as GeolocationPositionError
      if (error.code === 1) break
    }
  }
  let permission: PermissionState | 'unknown' = 'unknown'
  try {
    permission = (await navigator.permissions?.query({ name: 'geolocation' }))?.state ?? 'unknown'
  } catch {
    /* Safari before 16 has no geolocation permission query */
  }
  const failure = classify(error?.code ?? 2, permission, env)
  return { failure, help: help(failure, env) }
}
