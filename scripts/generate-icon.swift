import AppKit
import Foundation

// Draw the same vector geometry at full resolution for every platform icon.
let size = 1024
let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()
let background = NSBezierPath(roundedRect: NSRect(x: 38, y: 38, width: 948, height: 948), xRadius: 220, yRadius: 220)
NSColor(calibratedRed: 0.18, green: 0.32, blue: 0.22, alpha: 1).setFill()
background.fill()
let center = NSPoint(x: 420, y: 620)
for (diameter, width, alpha) in [(360.0, 38.0, 0.9), (195.0, 38.0, 0.9), (54.0, 0.0, 1.0)] {
    let rect = NSRect(x: center.x - diameter / 2, y: center.y - diameter / 2, width: diameter, height: diameter)
    let circle = NSBezierPath(ovalIn: rect)
    NSColor(calibratedWhite: 1, alpha: alpha).set()
    if width == 0 { circle.fill() } else { circle.lineWidth = width; circle.stroke() }
}
let pointer = NSBezierPath()
pointer.move(to: NSPoint(x: 520, y: 498))
pointer.line(to: NSPoint(x: 520, y: 195))
pointer.line(to: NSPoint(x: 597, y: 267))
pointer.line(to: NSPoint(x: 655, y: 142))
pointer.line(to: NSPoint(x: 716, y: 171))
pointer.line(to: NSPoint(x: 658, y: 296))
pointer.line(to: NSPoint(x: 768, y: 309))
pointer.close()
pointer.lineJoinStyle = .round
NSColor(calibratedRed: 0.08, green: 0.17, blue: 0.11, alpha: 1).setStroke()
pointer.lineWidth = 40
pointer.stroke()
NSColor.white.setFill()
pointer.fill()
image.unlockFocus()
guard let data = image.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: data),
      let png = bitmap.representation(using: .png, properties: [:]) else {
    fatalError("Could not render icon")
}
let output = CommandLine.arguments.dropFirst().first ?? "src-tauri/icons/icon.png"
try png.write(to: URL(fileURLWithPath: output), options: .atomic)
