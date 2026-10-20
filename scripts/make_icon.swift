import AppKit

// Draws the app icon (opaque, 1024 px) and the launch glyph (transparent, 480 px).
// Run it through scripts/make_icons.sh, which also writes the sizes the iOS and Android projects need.
// Usage: swift make_icon.swift <icon.png> <launch.png>

let blue = NSColor(red: 0.0, green: 0.235, blue: 0.424, alpha: 1)       // #003C6C
let gold = NSColor(red: 0.992, green: 0.78, blue: 0.0, alpha: 1)        // #FDC700
let white = NSColor.white

func render(size: Int, draw: (CGFloat) -> Void) -> Data {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
        samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .high
    draw(CGFloat(size))
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

/// The same picture as a PNG with no alpha channel, which the App Store wants for the icon.
func withoutAlpha(_ data: Data) -> Data {
    let cg = NSBitmapImageRep(data: data)!.cgImage!
    let ctx = CGContext(
        data: nil, width: cg.width, height: cg.height, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    ctx.draw(cg, in: CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
    return NSBitmapImageRep(cgImage: ctx.makeImage()!).representation(using: .png, properties: [:])!
}

/// The route and pin, drawn in a 1000 x 1000 box scaled to `s`.
func glyph(_ s: CGFloat, pinInner: NSColor) {
    let k = s / 1000
    func p(_ x: CGFloat, _ y: CGFloat) -> NSPoint { NSPoint(x: x * k, y: y * k) }

    // the walk: a trail of dots from the bottom left up to the pin
    let p0 = (x: 215.0, y: 205.0), p1 = (x: 430.0, y: 150.0), p2 = (x: 560.0, y: 300.0), p3 = (x: 655.0, y: 400.0)
    func bezier(_ t: Double) -> NSPoint {
        let u = 1 - t
        let x = u*u*u*p0.x + 3*u*u*t*p1.x + 3*u*t*t*p2.x + t*t*t*p3.x
        let y = u*u*u*p0.y + 3*u*u*t*p1.y + 3*u*t*t*p2.y + t*t*t*p3.y
        return NSPoint(x: x, y: y)
    }
    // equal steps along the curve, not equal steps in t
    var samples: [NSPoint] = []
    var lengths: [Double] = [0.0]
    for i in 0...400 {
        let point: NSPoint = bezier(Double(i) / 400.0)
        if i > 0 {
            let last: NSPoint = samples[i - 1]
            let step: Double = Double(hypot(point.x - last.x, point.y - last.y))
            lengths.append(lengths[i - 1] + step)
        }
        samples.append(point)
    }
    let total: Double = lengths[400]
    white.setFill()
    let radii: [Double] = [29.0, 32.0, 35.0, 38.0, 41.0]
    for i in 0..<radii.count {
        let radius: Double = radii[i]
        let want: Double = total * (0.21 + 0.155 * Double(i))
        var at = 400
        for j in 0...400 where lengths[j] >= want {
            at = j
            break
        }
        let c: NSPoint = samples[at]
        let rect = NSRect(x: (Double(c.x) - radius) * Double(k), y: (Double(c.y) - radius) * Double(k), width: 2 * radius * Double(k), height: 2 * radius * Double(k))
        NSBezierPath(ovalIn: rect).fill()
    }

    // where it starts
    white.setFill()
    NSBezierPath(ovalIn: NSRect(x: (215 - 58) * k, y: (205 - 58) * k, width: 116 * k, height: 116 * k)).fill()
    pinInner.setFill()
    NSBezierPath(ovalIn: NSRect(x: (215 - 26) * k, y: (205 - 26) * k, width: 52 * k, height: 52 * k)).fill()

    // the pin: a gold drop with a hole
    let pin = NSBezierPath()
    let cx: CGFloat = 690, cy: CGFloat = 690, r: CGFloat = 150
    pin.appendOval(in: NSRect(x: (cx - r) * k, y: (cy - r) * k, width: 2 * r * k, height: 2 * r * k))
    let tail = NSBezierPath()
    tail.move(to: p(cx - r * 0.93, cy - r * 0.36))
    tail.line(to: p(cx, cy - r * 2.05))
    tail.line(to: p(cx + r * 0.93, cy - r * 0.36))
    tail.close()
    gold.setFill()
    pin.fill()
    tail.fill()
    pinInner.setFill()
    NSBezierPath(ovalIn: NSRect(x: (cx - 58) * k, y: (cy - 58) * k, width: 116 * k, height: 116 * k)).fill()
}

let icon = withoutAlpha(render(size: 1024) { s in
    blue.setFill()
    NSBezierPath.fill(NSRect(x: 0, y: 0, width: s, height: s))
    glyph(s, pinInner: blue)
})
try icon.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))

let launch = render(size: 480) { s in
    glyph(s, pinInner: blue)
}
try launch.write(to: URL(fileURLWithPath: CommandLine.arguments[2]))
print("icon \(icon.count) bytes, launch glyph \(launch.count) bytes")
