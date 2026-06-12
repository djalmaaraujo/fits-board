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
let base = roundedRect(canvas.insetBy(dx: 64, dy: 64), radius: 220)
let shadow = NSShadow()
shadow.shadowColor = NSColor.black.withAlphaComponent(0.42)
shadow.shadowOffset = CGSize(width: 0, height: -28)
shadow.shadowBlurRadius = 58
shadow.set()
color(0x08090b).setFill()
base.fill()
NSShadow().set()

let inner = roundedRect(canvas.insetBy(dx: 92, dy: 92), radius: 184)
color(0x12151b).setFill()
inner.fill()

let topGlow = roundedRect(CGRect(x: 126, y: 538, width: 772, height: 338), radius: 140)
let gradient = NSGradient(colors: [
    color(0x1b4dff, alpha: 0.42),
    color(0x24d36a, alpha: 0.14),
    color(0x12151b, alpha: 0.02)
])!
gradient.draw(in: topGlow, angle: -18)

let badge = roundedRect(CGRect(x: 142, y: 566, width: 276, height: 276), radius: 76)
let badgeGradient = NSGradient(colors: [
    color(0x1475ff),
    color(0x0f4fe8)
])!
badgeGradient.draw(in: badge, angle: 45)
color(0xffffff, alpha: 0.16).setStroke()
badge.lineWidth = 4
badge.stroke()

let f = NSString(string: "F")
let fAttributes: [NSAttributedString.Key: Any] = [
    .font: NSFont.monospacedSystemFont(ofSize: 178, weight: .heavy),
    .foregroundColor: NSColor.white,
    .kern: -5
]
let fSize = f.size(withAttributes: fAttributes)
f.draw(
    at: CGPoint(x: 142 + (276 - fSize.width) / 2 - 2, y: 566 + (276 - fSize.height) / 2 + 2),
    withAttributes: fAttributes
)

let board = roundedRect(CGRect(x: 456, y: 586, width: 420, height: 214), radius: 54)
color(0x0b0d12, alpha: 0.72).setFill()
board.fill()
color(0xffffff, alpha: 0.12).setStroke()
board.lineWidth = 3
board.stroke()

let laneY: CGFloat = 692
let lane = NSBezierPath()
lane.move(to: CGPoint(x: 508, y: laneY))
lane.line(to: CGPoint(x: 818, y: laneY))
color(0x2dd46f).setStroke()
lane.lineWidth = 18
lane.lineCapStyle = .round
lane.stroke()

for index in 0..<4 {
    let x = CGFloat(532 + index * 74)
    let capsule = roundedRect(CGRect(x: x, y: 724, width: 54, height: 28), radius: 14)
    color(index < 3 ? 0x2dd46f : 0x2f8cff, alpha: index < 3 ? 0.92 : 0.95).setFill()
    capsule.fill()
}

for index in 0..<3 {
    let x = CGFloat(586 + index * 74)
    let chevron = NSBezierPath()
    chevron.move(to: CGPoint(x: x, y: 663))
    chevron.line(to: CGPoint(x: x + 22, y: 692))
    chevron.line(to: CGPoint(x: x, y: 721))
    color(0xffffff, alpha: 0.74).setStroke()
    chevron.lineWidth = 10
    chevron.lineJoinStyle = .round
    chevron.lineCapStyle = .round
    chevron.stroke()
}

let finalStop = roundedRect(CGRect(x: 782, y: 656, width: 46, height: 72), radius: 18)
color(0xffffff, alpha: 0.90).setFill()
finalStop.fill()

let title = NSString(string: "FITS")
let titleAttributes: [NSAttributedString.Key: Any] = [
    .font: NSFont.monospacedSystemFont(ofSize: 88, weight: .heavy),
    .foregroundColor: color(0xf0f4ff),
    .kern: 9
]
title.draw(at: CGPoint(x: 154, y: 278), withAttributes: titleAttributes)

let subtitle = NSString(string: "BOARD")
let subtitleAttributes: [NSAttributedString.Key: Any] = [
    .font: NSFont.monospacedSystemFont(ofSize: 42, weight: .bold),
    .foregroundColor: color(0x7d8594),
    .kern: 7
]
subtitle.draw(at: CGPoint(x: 164, y: 222), withAttributes: subtitleAttributes)

let underline = roundedRect(CGRect(x: 154, y: 184, width: 300, height: 16), radius: 8)
color(0x2dd46f).setFill()
underline.fill()

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
