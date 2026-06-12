import AppKit
import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let resources = root.appendingPathComponent("Resources", isDirectory: true)
let iconset = resources.appendingPathComponent("FitsBoard.iconset", isDirectory: true)
let png1024 = resources.appendingPathComponent("FitsBoardIcon-1024.png")

try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

let size = CGSize(width: 1024, height: 1024)
let image = NSImage(size: size)

func color(_ hex: UInt32, alpha: CGFloat = 1) -> NSColor {
    NSColor(
        calibratedRed: CGFloat((hex >> 16) & 0xff) / 255,
        green: CGFloat((hex >> 8) & 0xff) / 255,
        blue: CGFloat(hex & 0xff) / 255,
        alpha: alpha
    )
}

func roundedRect(_ rect: CGRect, radius: CGFloat) -> NSBezierPath {
    NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
}

image.lockFocus()
NSGraphicsContext.current?.imageInterpolation = .high

let canvas = CGRect(origin: .zero, size: size)
let base = roundedRect(canvas.insetBy(dx: 86, dy: 86), radius: 190)
color(0x05080d).setFill()
base.fill()

let inner = roundedRect(canvas.insetBy(dx: 86, dy: 86), radius: 190)
let innerGradient = NSGradient(colors: [
    color(0x0b1824),
    color(0x05080d)
])!
innerGradient.draw(in: inner, angle: 90)

let fullGlow = roundedRect(canvas.insetBy(dx: 86, dy: 86), radius: 190)
let fullGlowGradient = NSGradient(colors: [
    color(0x2f8cff, alpha: 0.11),
    color(0x0b1824, alpha: 0.04),
    color(0x05080d, alpha: 0.02)
])!
fullGlowGradient.draw(in: fullGlow, angle: 90)

let laneY: CGFloat = 420
let laneStart: CGFloat = 190
let stopX: CGFloat = 758
let stopWidth: CGFloat = 72
let stopHeight: CGFloat = 112
let stopY: CGFloat = 364
let drawingEnd = stopX + stopWidth

let lane = NSBezierPath()
lane.move(to: CGPoint(x: laneStart, y: laneY))
lane.line(to: CGPoint(x: stopX + 22, y: laneY))
color(0x31d779).setStroke()
lane.lineWidth = 36
lane.lineCapStyle = .round
lane.stroke()

let nodeY: CGFloat = 586
let nodes: [(CGFloat, CGFloat, UInt32)] = [
    (laneStart, 64, 0x31d779),
    (314, 70, 0x31d779),
    (438, 78, 0x31d779),
    (drawingEnd - 92, 92, 0x40a8ff)
]

for (x, width, hex) in nodes {
    let node = roundedRect(CGRect(x: x, y: nodeY, width: width, height: 34), radius: 17)
    color(hex).setFill()
    node.fill()
}

for x in [326, 456, 586] as [CGFloat] {
    let chevron = NSBezierPath()
    chevron.move(to: CGPoint(x: x, y: 364))
    chevron.line(to: CGPoint(x: x + 46, y: laneY))
    chevron.line(to: CGPoint(x: x, y: 476))
    color(0xe7ecef, alpha: 0.86).setStroke()
    chevron.lineWidth = 26
    chevron.lineJoinStyle = .round
    chevron.lineCapStyle = .round
    chevron.stroke()
}

let stopShadow = NSShadow()
stopShadow.shadowColor = NSColor.black.withAlphaComponent(0.30)
stopShadow.shadowOffset = CGSize(width: 0, height: -7)
stopShadow.shadowBlurRadius = 14
stopShadow.set()
let finalStop = roundedRect(CGRect(x: stopX, y: stopY, width: stopWidth, height: stopHeight), radius: 32)
let stopGradient = NSGradient(colors: [
    color(0xffffff, alpha: 0.98),
    color(0xd8dde0, alpha: 0.96)
])!
stopGradient.draw(in: finalStop, angle: 90)
NSShadow().set()
color(0xffffff, alpha: 0.18).setStroke()
finalStop.lineWidth = 3
finalStop.stroke()

image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiff),
      let png = bitmap.representation(using: .png, properties: [:]) else {
    fatalError("Could not render icon PNG.")
}
try png.write(to: png1024)

let iconSizes: [(String, CGFloat)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024)
]

for (name, dimension) in iconSizes {
    let resized = NSImage(size: CGSize(width: dimension, height: dimension))
    resized.lockFocus()
    NSGraphicsContext.current?.imageInterpolation = .high
    image.draw(in: CGRect(x: 0, y: 0, width: dimension, height: dimension))
    resized.unlockFocus()

    guard let tiff = resized.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff),
          let png = bitmap.representation(using: .png, properties: [:]) else {
        fatalError("Could not render \(name).")
    }
    try png.write(to: iconset.appendingPathComponent(name))
}

func normalizePixels(_ url: URL, dimension: Int) throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/sips")
    process.arguments = ["-z", "\(dimension)", "\(dimension)", url.path]
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    try process.run()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
        fatalError("Could not normalize \(url.lastPathComponent).")
    }
}

try normalizePixels(png1024, dimension: 1024)
for (name, dimension) in iconSizes {
    try normalizePixels(iconset.appendingPathComponent(name), dimension: Int(dimension))
}
