import Carbon
import Foundation
import AppKit

// Independent control for determining whether synthetic key events can reach
// the same Carbon global-hotkey API used by the application on this runner.
let application = NSApplication.shared
application.setActivationPolicy(.accessory)
var handler: EventHandlerRef?
var hotkey: EventHotKeyRef?
var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
let callback: EventHandlerUPP = { _, _, _ in
    print("Carbon control hotkey received")
    fflush(stdout)
    return noErr
}
guard InstallEventHandler(GetApplicationEventTarget(), callback, 1, &spec, nil, &handler) == noErr else { fatalError("Cannot install Carbon handler") }
let hotkeyID = EventHotKeyID(signature: OSType(0x54455354), id: 1)
// F7, not the F8 registered by the application.
guard RegisterEventHotKey(98, UInt32(controlKey | shiftKey), hotkeyID, GetApplicationEventTarget(), 0, &hotkey) == noErr else { fatalError("Cannot register Carbon control hotkey") }
Timer.scheduledTimer(withTimeInterval: 12, repeats: false) { _ in application.terminate(nil) }
print("Carbon control ready"); fflush(stdout)
application.run()
if let hotkey { UnregisterEventHotKey(hotkey) }
if let handler { RemoveEventHandler(handler) }
