import Carbon.HIToolbox
import Foundation

/// A system-wide keyboard shortcut via Carbon's RegisterEventHotKey, which needs no Accessibility permission.
final class HotKey {
    private var ref: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private let action: () -> Void

    /// Default shortcut: ⌥⌘Y.
    init(keyCode: UInt32 = UInt32(kVK_ANSI_Y), modifiers: UInt32 = UInt32(optionKey | cmdKey), action: @escaping () -> Void) {
        self.action = action
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, _, userData in
            guard let userData else { return noErr }
            Unmanaged<HotKey>.fromOpaque(userData).takeUnretainedValue().action()
            return noErr
        }, 1, &spec, selfPtr, &handler)
        let id = EventHotKeyID(signature: OSType(0x464C_5253), id: 1) // "FLRS"
        RegisterEventHotKey(keyCode, modifiers, id, GetApplicationEventTarget(), 0, &ref)
    }

    deinit {
        if let ref { UnregisterEventHotKey(ref) }
        if let handler { RemoveEventHandler(handler) }
    }
}
