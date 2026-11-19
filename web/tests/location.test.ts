import { describe, expect, it } from 'vitest'
import { classify, environment, help } from '../src/state/location'

const UA = {
  macChrome: 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36',
  macSafari: 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/19.1 Safari/605.1.15',
  iphoneSafari: 'Mozilla/5.0 (iPhone; CPU iPhone OS 19_1 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/19.1 Mobile/15E148 Safari/604.1',
  iphoneChrome: 'Mozilla/5.0 (iPhone; CPU iPhone OS 19_1 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) CriOS/142.0 Mobile/15E148 Safari/604.1',
  iphoneInstagram: 'Mozilla/5.0 (iPhone; CPU iPhone OS 19_1 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148 Instagram 400.0.0',
  iphoneWebView: 'Mozilla/5.0 (iPhone; CPU iPhone OS 19_1 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148',
  ipadDesktop: 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/19.1 Safari/605.1.15',
  androidChrome: 'Mozilla/5.0 (Linux; Android 15; Pixel 9) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Mobile Safari/537.36',
  androidWebView: 'Mozilla/5.0 (Linux; Android 15; Pixel 9; wv) AppleWebKit/537.36 (KHTML, like Gecko) Version/4.0 Chrome/142.0.0.0 Mobile Safari/537.36',
  windowsEdge: 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36 Edg/142.0.0.0',
}

describe('where location is blocked', () => {
  it('reads the device, browser and in-app browsers from the user agent', () => {
    expect(environment(UA.macChrome)).toEqual({ platform: 'mac', browser: 'chrome', inApp: null })
    expect(environment(UA.macSafari)).toEqual({ platform: 'mac', browser: 'safari', inApp: null })
    expect(environment(UA.iphoneSafari)).toEqual({ platform: 'ios', browser: 'safari', inApp: null })
    expect(environment(UA.iphoneChrome)).toEqual({ platform: 'ios', browser: 'chrome', inApp: null })
    expect(environment(UA.iphoneInstagram).inApp).toBe('Instagram')
    expect(environment(UA.iphoneWebView).inApp).toBe('another app')
    expect(environment(UA.ipadDesktop, 5).platform).toBe('ios')
    expect(environment(UA.androidChrome)).toEqual({ platform: 'android', browser: 'chrome', inApp: null })
    expect(environment(UA.androidWebView).inApp).toBe('another app')
    expect(environment(UA.windowsEdge)).toEqual({ platform: 'windows', browser: 'edge', inApp: null })
  })
  it('blames the operating system when the site is allowed but the position is refused', () => {
    const env = environment(UA.macChrome)
    expect(classify(1, 'granted', env)).toBe('blocked-system')
    const h = help('blocked-system', env)
    expect(h.title).toBe('Location is off for Chrome on this Mac')
    expect(h.steps.join(' ')).toContain('System Settings → Privacy & Security → Location Services')
    expect(h.steps.join(' ')).toContain('switch on Google Chrome')
  })
  it('points iPhone Safari at Safari Websites in Location Services', () => {
    const env = environment(UA.iphoneSafari)
    expect(help(classify(1, 'granted', env), env).steps.join(' ')).toContain('Safari Websites')
    expect(help(classify(1, 'unknown', env), env).steps.join(' ')).toMatch(/Safari Websites.*Website Settings/)
  })
  it('tells people in an app to open the page in a browser', () => {
    const env = environment(UA.iphoneInstagram)
    expect(classify(1, 'granted', env)).toBe('in-app')
    expect(help('in-app', env).title).toBe('Open this page in Safari')
  })
  it('separates a blocked site, a slow fix and no fix', () => {
    const env = environment(UA.androidChrome)
    expect(classify(1, 'denied', env)).toBe('blocked-site')
    expect(classify(3, 'granted', env)).toBe('timeout')
    expect(classify(2, 'granted', env)).toBe('unavailable')
  })
})
