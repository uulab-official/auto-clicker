import Foundation
import ApplicationServices
import AppKit

guard ProcessInfo.processInfo.environment["GITHUB_ACTIONS"] == "true",
      ProcessInfo.processInfo.environment["RUNNER_ENVIRONMENT"] == "github-hosted" else {
    fputs("Requires a disposable GitHub-hosted runner\n", stderr); exit(2)
}
guard AXIsProcessTrusted() else { fputs("Accessibility permission unavailable\n", stderr); exit(3) }
let args = CommandLine.arguments
guard args.count >= 3, let pid = Int32(args[2]) else { exit(2) }
let root = AXUIElementCreateApplication(pid)
func attr(_ item: AXUIElement, _ name: CFString) -> CFTypeRef? {
    var value: CFTypeRef?
    return AXUIElementCopyAttributeValue(item, name, &value) == .success ? value : nil
}
func visit(_ item: AXUIElement, _ depth: Int, _ body: (AXUIElement) -> Bool) -> Bool {
    if depth > 50 { return false }
    if body(item) { return true }
    if let children = attr(item, kAXChildrenAttribute as CFString) as? [AXUIElement] {
        for child in children where visit(child, depth + 1, body) { return true }
    }
    return false
}
func text(_ item: AXUIElement, _ name: CFString) -> String { (attr(item, name) as? String) ?? "" }
func dump() {
    _ = visit(root, 0) { item in
        let role = text(item, kAXRoleAttribute as CFString)
        let title = text(item, kAXTitleAttribute as CFString)
        let desc = text(item, kAXDescriptionAttribute as CFString)
        let value = text(item, kAXValueAttribute as CFString)
        if !title.isEmpty || !desc.isEmpty || !value.isEmpty { print("\(role): \(title) | \(desc) | \(value)") }
        return false
    }
}
func key(_ code: CGKeyCode, _ down: Bool, _ flags: CGEventFlags = []) {
    guard let event = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: down) else { exit(3) }
    event.flags = flags; event.post(tap: .cghidEventTap)
    Thread.sleep(forTimeInterval: 0.08)
}
func tap(_ code: CGKeyCode, _ flags: CGEventFlags = []) { key(code, true, flags); key(code, false, flags) }
func typeText(_ value: String) {
    for unit in value.utf16 {
        var utf16 = unit
        for down in [true, false] {
            guard let event = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: down) else { exit(3) }
            event.keyboardSetUnicodeString(stringLength: 1, unicodeString: &utf16)
            event.post(tap: .cghidEventTap)
        }
    }
}
switch args[1] {
case "dump": dump()
case "press":
    guard args.count == 4 else { exit(2) }
    for _ in 0..<80 {
        if visit(root, 0, { item in
            let title = text(item, kAXTitleAttribute as CFString), desc = text(item, kAXDescriptionAttribute as CFString)
            guard title == args[3] || desc == args[3] else { return false }
            var names: CFArray?
            guard AXUIElementCopyActionNames(item, &names) == .success,
                  ((names as? [String])?.contains(kAXPressAction as String) ?? false) else { return false }
            return AXUIElementPerformAction(item, kAXPressAction as CFString) == .success
        }) { print("Pressed \(args[3]) in app \(pid)"); exit(0) }
        Thread.sleep(forTimeInterval: 0.25)
    }
    dump(); fputs("Control unavailable: \(args[3])\n", stderr); exit(1)
case "path":
    guard args.count == 4 else { exit(2) }
    // UI and global input are confined to this disposable CI VM. Activate the
    // exact app, invoke the native panel's Go to Folder and type the path.
    guard let app = NSRunningApplication(processIdentifier: pid) else { exit(1) }
    _ = app.activate(options: [])
    Thread.sleep(forTimeInterval: 1)
    key(55, true, [.maskCommand]); key(56, true, [.maskCommand, .maskShift])
    tap(5, [.maskCommand, .maskShift]) // Command-Shift-G
    key(56, false, [.maskCommand]); key(55, false)
    Thread.sleep(forTimeInterval: 0.8)
    typeText(args[3]); Thread.sleep(forTimeInterval: 0.5)
    print("Native panel after entering path:")
    _ = visit(root, 0) { item in
        let role = text(item, kAXRoleAttribute as CFString)
        let title = text(item, kAXTitleAttribute as CFString), desc = text(item, kAXDescriptionAttribute as CFString), value = text(item, kAXValueAttribute as CFString)
        if role == "AXSheet" || (role == "AXTextField" && value.contains("/")) || (role == "AXButton" && ["Go", "Open", "Save", "Cancel"].contains(title)) { print("\(role): \(title) | \(desc) | \(value)") }
        return false
    }
    tap(36) // Return
    Thread.sleep(forTimeInterval: 1.5); tap(36) // Open or Save
case "cancel":
    guard let app = NSRunningApplication(processIdentifier: pid) else { exit(1) }
    _ = app.activate(options: []); Thread.sleep(forTimeInterval: 1); tap(53) // Escape
default: exit(2)
}
