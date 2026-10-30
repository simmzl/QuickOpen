import Carbon
import Foundation

private let quickOpenHotKeyHandler: EventHandlerUPP = { _, event, userData in
    guard let event, let userData else { return OSStatus(eventNotHandledErr) }
    let manager = Unmanaged<GlobalHotKeyManager>.fromOpaque(userData).takeUnretainedValue()
    return manager.handle(event: event)
}

final class GlobalHotKeyManager {
    private static let signature: OSType = 0x516B4F70 // "QkOp"

    private var eventHandler: EventHandlerRef?
    private var hotKeyRefs: [UUID: EventHotKeyRef] = [:]
    private var actions: [UInt32: () -> Void] = [:]
    private var nextNumericID: UInt32 = 1

    init() {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            quickOpenHotKeyHandler,
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandler
        )
        if status != noErr {
            NSLog("QuickOpen: failed to install global hotkey handler (%d)", status)
        }
    }

    deinit {
        unregisterAll()
        if let eventHandler { RemoveEventHandler(eventHandler) }
    }

    @discardableResult
    func register(id: UUID, hotKey: HotKey, action: @escaping () -> Void) -> OSStatus {
        if let existing = hotKeyRefs.removeValue(forKey: id) {
            UnregisterEventHotKey(existing)
        }

        let numericID = nextNumericID
        nextNumericID &+= 1
        let identifier = EventHotKeyID(signature: Self.signature, id: numericID)
        var reference: EventHotKeyRef?
        let status = RegisterEventHotKey(
            hotKey.keyCode,
            hotKey.modifiers,
            identifier,
            GetApplicationEventTarget(),
            OptionBits(0),
            &reference
        )

        if status == noErr, let reference {
            hotKeyRefs[id] = reference
            actions[numericID] = action
        }
        return status
    }

    func unregisterAll() {
        hotKeyRefs.values.forEach { UnregisterEventHotKey($0) }
        hotKeyRefs.removeAll()
        actions.removeAll()
    }

    fileprivate func handle(event: EventRef) -> OSStatus {
        var identifier = EventHotKeyID()
        let status = GetEventParameter(
            event,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &identifier
        )
        guard status == noErr, identifier.signature == Self.signature else { return status }
        guard let action = actions[identifier.id] else { return OSStatus(eventNotHandledErr) }
        action()
        return noErr
    }
}
