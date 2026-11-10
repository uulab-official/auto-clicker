import Foundation
import ApplicationServices

guard AXIsProcessTrusted() else {
    fputs("Accessibility permission unavailable on disposable runner\n", stderr); exit(3)
}
let args = CommandLine.arguments
guard args.count >= 2 else { exit(2) }
if args[1] == "move", args.count == 4, let x = Double(args[2]), let y = Double(args[3]) {
    let point = CGPoint(x: x, y: y)
    guard CGWarpMouseCursorPosition(point) == .success else { exit(1) }
    exit(0)
}
if args[1] == "stop" {
    // F8 is keycode 100. The shortcut is delivered only inside the disposable VM.
    guard let down = CGEvent(keyboardEventSource: nil, virtualKey: 100, keyDown: true),
          let up = CGEvent(keyboardEventSource: nil, virtualKey: 100, keyDown: false) else { exit(1) }
    down.flags = [.maskControl, .maskShift]; up.flags = [.maskControl, .maskShift]
    down.post(tap: .cghidEventTap); up.post(tap: .cghidEventTap)
    exit(0)
}
guard args[1] == "start", args.count == 3, let pid = Int32(args[2]) else { exit(2) }
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
    let labels = Set(["Start clicking", "클릭 시작", "クリックを開始"])
    if role == "AXButton" && (labels.contains(title) || labels.contains(desc)) {
        return AXUIElementPerformAction(item, kAXPressAction as CFString) == .success
    }
    if let children = attr(item, kAXChildrenAttribute as CFString) as? [AXUIElement] {
        for child in children where press(child, depth + 1) { return true }
    }
    return false
}
for _ in 0..<60 {
    if press(root, 0) { print("Pressed Start clicking in public app PID \(pid)"); exit(0) }
    Thread.sleep(forTimeInterval: 1)
}
fputs("Could not invoke Start clicking in public app\n", stderr); exit(1)
