import Foundation
import ApplicationServices

// AXPress is delivered to an element of this specific app process, not to the
// desktop pointer or keyboard. The caller must already be trusted by macOS.
let probe = CommandLine.arguments.count > 2 && CommandLine.arguments[2] == "probe"
let names = probe ? Set(["Start clicking", "클릭 시작", "クリックを開始"]) : Set(["Install update", "업데이트 설치", "アップデートをインストール"])
guard CommandLine.arguments.count >= 2, let pid = Int32(CommandLine.arguments[1]) else {
    fputs("Expected application PID\n", stderr); exit(2)
}
guard AXIsProcessTrusted() else {
    fputs("This isolated runner has not granted Accessibility access to the test client; cannot invoke the update button.\n", stderr); exit(3)
}
let root = AXUIElementCreateApplication(pid)
var seen = Set<String>()
func attribute(_ item: AXUIElement, _ name: CFString) -> CFTypeRef? {
    var result: CFTypeRef?
    return AXUIElementCopyAttributeValue(item, name, &result) == .success ? result : nil
}
func scan(_ item: AXUIElement, _ depth: Int) -> Bool {
    if depth > 45 { return false }
    let role = (attribute(item, kAXRoleAttribute as CFString) as? String) ?? ""
    let title = (attribute(item, kAXTitleAttribute as CFString) as? String) ?? ""
    let description = (attribute(item, kAXDescriptionAttribute as CFString) as? String) ?? ""
    if role == "AXButton" {
        seen.insert(title + " | " + description)
        if names.contains(title) || names.contains(description) {
            if probe { print("Target application button accessible: \(title) \(description)"); return true }
            if AXUIElementPerformAction(item, kAXPressAction as CFString) == .success {
                print("Invoked update button in app PID \(pid): \(title) \(description)")
                return true
            }
        }
    }
    if let children = attribute(item, kAXChildrenAttribute as CFString) as? [AXUIElement] {
        for child in children where scan(child, depth + 1) { return true }
    }
    return false
}
let deadline = Date().addingTimeInterval(90)
while Date() < deadline {
    if scan(root, 0) { exit(0) }
    Thread.sleep(forTimeInterval: 1)
}
fputs("Update button unavailable in target app accessibility tree. Buttons observed: \(seen.sorted())\n", stderr)
exit(1)
