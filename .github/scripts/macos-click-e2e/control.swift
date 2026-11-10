import Foundation
import ApplicationServices

guard AXIsProcessTrusted() else {
    fputs("Accessibility permission unavailable on disposable runner\n", stderr); exit(3)
}
let args = CommandLine.arguments
guard args.count >= 2 else { exit(2) }
if args[1] == "monitor" {
    let mask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue) | (1 << CGEventType.flagsChanged.rawValue)
    let callback: CGEventTapCallBack = { _, type, event, _ in
        print("keyboard event type=\(type.rawValue) code=\(event.getIntegerValueField(.keyboardEventKeycode)) flags=\(event.flags.rawValue)")
        fflush(stdout)
        return Unmanaged.passUnretained(event)
    }
    guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .listenOnly, eventsOfInterest: CGEventMask(mask), callback: callback, userInfo: nil),
          let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
        fputs("Cannot observe keyboard event delivery on runner\n", stderr); exit(3)
    }
    CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .defaultMode)
    CGEvent.tapEnable(tap: tap, enable: true)
    print("Keyboard monitor ready"); fflush(stdout)
    CFRunLoopRunInMode(.defaultMode, 10, false)
    exit(0)
}
if args[1] == "move", args.count == 4, let x = Double(args[2]), let y = Double(args[3]) {
    let point = CGPoint(x: x, y: y)
    guard CGWarpMouseCursorPosition(point) == .success else { exit(1) }
    exit(0)
}
if args[1] == "stop" {
    // Send modifier key transitions as well as the F8 key. Flags on F8 alone
    // do not establish modifier state for every global shortcut listener.
    func key(_ code: CGKeyCode, _ down: Bool, _ flags: CGEventFlags) {
        guard let event = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: down) else { exit(1) }
        event.flags = flags
        event.post(tap: .cghidEventTap)
        Thread.sleep(forTimeInterval: 0.08)
    }
    key(59, true, [.maskControl]); key(56, true, [.maskControl, .maskShift])
    key(100, true, [.maskControl, .maskShift]); key(100, false, [.maskControl, .maskShift])
    key(56, false, [.maskControl]); key(59, false, [])
    exit(0)
}
guard ["start", "dump", "button"].contains(args[1]), args.count >= 3, let pid = Int32(args[2]) else { exit(2) }
if args[1] == "button" && (args.count != 5 || Int(args[4]) == nil) { exit(2) }
let labels = args[1] == "button" ? Set([args[3]]) : Set(["Start clicking", "클릭 시작", "クリックを開始"])
let wanted = args[1] == "button" ? (Int(args[4]) ?? 0) : 0
var matching = 0
let root = AXUIElementCreateApplication(pid)
func attr(_ item: AXUIElement, _ name: CFString) -> CFTypeRef? {
    var value: CFTypeRef?
    return AXUIElementCopyAttributeValue(item, name, &value) == .success ? value : nil
}
func press(_ item: AXUIElement, _ depth: Int) -> Bool {
    if depth > 45 { return false }
    let role = (attr(item, kAXRoleAttribute as CFString) as? String) ?? ""
    let title = (attr(item, kAXTitleAttribute as CFString) as? String) ?? ""
    let desc = (attr(item, kAXDescriptionAttribute as CFString) as? String) ?? ""
    if role == "AXButton" && (labels.contains(title) || labels.contains(desc)) {
        let current = matching; matching += 1
        if current == wanted { return AXUIElementPerformAction(item, kAXPressAction as CFString) == .success }
    }
    if let children = attr(item, kAXChildrenAttribute as CFString) as? [AXUIElement] {
        for child in children where press(child, depth + 1) { return true }
    }
    return false
}
func dump(_ item: AXUIElement, _ depth: Int) {
    if depth > 45 { return }
    let role = (attr(item, kAXRoleAttribute as CFString) as? String) ?? ""
    let title = (attr(item, kAXTitleAttribute as CFString) as? String) ?? ""
    let desc = (attr(item, kAXDescriptionAttribute as CFString) as? String) ?? ""
    let value = (attr(item, kAXValueAttribute as CFString) as? String) ?? ""
    if !title.isEmpty || !desc.isEmpty || !value.isEmpty { print("\(role): \(title) | \(desc) | \(value)") }
    if let children = attr(item, kAXChildrenAttribute as CFString) as? [AXUIElement] {
        for child in children { dump(child, depth + 1) }
    }
}
if args[1] == "dump" { dump(root, 0); exit(0) }
for _ in 0..<60 {
    matching = 0
    if press(root, 0) { print("Pressed \(labels) in public app PID \(pid)"); exit(0) }
    Thread.sleep(forTimeInterval: 1)
}
fputs("Could not invoke \(labels) in public app\n", stderr); exit(1)
