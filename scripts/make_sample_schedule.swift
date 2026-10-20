import AppKit

// Draws an invented class schedule in the layout of the MyUCSC "Class Schedule" page, for trying picture
// import without anyone's real schedule.
// Usage: swift make_sample_schedule.swift out.png

let width = 1500
let height = 880
let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8, samplesPerPixel: 4,
    hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

func fill(_ color: NSColor, x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat) {
    color.setFill()
    NSBezierPath.fill(NSRect(x: x, y: CGFloat(height) - y - h, width: w, height: h))
}

func text(_ s: String, x: CGFloat, y: CGFloat, size: CGFloat = 24, bold: Bool = false, color: NSColor = .black) {
    let font = bold ? NSFont.boldSystemFont(ofSize: size) : NSFont.systemFont(ofSize: size)
    let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
    (s as NSString).draw(at: NSPoint(x: x, y: CGFloat(height) - y - size * 1.2), withAttributes: attrs)
}

fill(.white, x: 0, y: 0, w: CGFloat(width), h: CGFloat(height))
text("My Class Schedule", x: 30, y: 24, size: 34, bold: true, color: NSColor(red: 0, green: 0.24, blue: 0.42, alpha: 1))
text("Fall 2026 | University of Example (sample data)", x: 30, y: 74, size: 22, color: .darkGray)

let cols: [CGFloat] = [30, 150, 250, 400, 730, 1010, 1240]
let heads = ["Class Nbr", "Section", "Component", "Days & Times", "Room", "Instructor", "Start/End Date"]

struct Course {
    let title: String
    let status: String
    let units: String
    let rows: [[String]]
}

let courses = [
    Course(title: "XYZ 10 - Sample Calculus", status: "Enrolled", units: "5.00", rows: [
        ["10001", "01A", "Discussion", "Tu 9:00AM - 9:55AM", "Soc Sci 2 075", "To be Announced", "09/24/2026 - 12/04/2026"],
        ["10002", "01", "Lecture", "MoWeFr 1:20PM - 2:25PM", "Kresge Acad 3201", "A Instructor", "09/24/2026 - 12/04/2026"],
    ]),
    Course(title: "ABC 20 - Sample Systems Design", status: "Enrolled", units: "5.00", rows: [
        ["10003", "01", "Lecture", "TuTh 11:40AM - 1:15PM", "Earth&Marine B206", "B Instructor", "09/24/2026 - 12/04/2026"],
        ["10004", "01A", "Discussion", "Th 4:00PM - 5:05PM", "Humn Lecture Hall", "To be Announced", "09/24/2026 - 12/04/2026"],
    ]),
    Course(title: "DEF 30 - Dropped Course", status: "Dropped", units: "5.00", rows: [
        ["10005", "01", "Lecture", "MoWe 8:00AM - 9:05AM", "J Baskin Engr 156", "C Instructor", "09/24/2026 - 12/04/2026"],
    ]),
]

var y: CGFloat = 130
for course in courses {
    fill(NSColor(white: 0.9, alpha: 1), x: 20, y: y, w: CGFloat(width) - 40, h: 44)
    text(course.title, x: 30, y: y + 8, size: 26, bold: true)
    y += 54
    text("Status", x: 30, y: y, size: 20, color: .gray)
    text("Units", x: 250, y: y, size: 20, color: .gray)
    text("Grading", x: 400, y: y, size: 20, color: .gray)
    text("Grade", x: 730, y: y, size: 20, color: .gray)
    y += 28
    text(course.status, x: 30, y: y)
    text(course.units, x: 250, y: y)
    text("Graded", x: 400, y: y)
    y += 42
    for (i, head) in heads.enumerated() { text(head, x: cols[i], y: y, size: 20, bold: true, color: .darkGray) }
    y += 30
    for row in course.rows {
        for (i, cell) in row.enumerated() { text(cell, x: cols[i], y: y, size: 22) }
        y += 38
    }
    y += 24
}

NSGraphicsContext.restoreGraphicsState()
let png = rep.representation(using: .png, properties: [:])!
try png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
print("wrote \(CommandLine.arguments[1]) (\(png.count) bytes)")
