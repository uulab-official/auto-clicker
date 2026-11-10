import AppKit

// A disposable target with its own event log. The clicker must send actual
// mouse events to this window; changing its log from the test is not enough.
let logPath = CommandLine.arguments[1]
FileManager.default.createFile(atPath: logPath, contents: nil)
let log = try FileHandle(forWritingTo: URL(fileURLWithPath: logPath))
func record(_ value: String) {
    log.write((value + "\n").data(using: .utf8)!)
    log.synchronizeFile()
}
class Target: NSView {
    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        record("click \(Int(point.x)) \(Int(point.y))")
    }
    override func draw(_ dirtyRect: NSRect) { NSColor.systemBlue.setFill(); dirtyRect.fill() }
}
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let rect = NSRect(x: 30, y: 30, width: 160, height: 160)
let window = NSPanel(contentRect: rect, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
window.level = .floating
window.contentView = Target(frame: NSRect(x: 0, y: 0, width: 160, height: 160))
window.orderFrontRegardless()
guard let screen = NSScreen.main else { fatalError("No GUI screen on runner") }
// CoreGraphics uses a top-left origin on the main display.
record("point \(Int(rect.midX)) \(Int(screen.frame.height - rect.midY))")
app.run()
