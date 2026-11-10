import Carbon
import Foundation

// Independent control for determining whether synthetic key events can reach
// the same Carbon global-hotkey API used by the application on this runner.
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
print("Carbon control ready"); fflush(stdout)
CFRunLoopRunInMode(.defaultMode, 12, false)
if let hotkey { UnregisterEventHotKey(hotkey) }
if let handler { RemoveEventHandler(handler) }
