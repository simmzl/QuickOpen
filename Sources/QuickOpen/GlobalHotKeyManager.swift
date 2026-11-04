import Carbon
import Foundation

private let quickOpenHotKeyHandler: EventHandlerUPP = { _, event, userData in
    guard let event, let userData else { return OSStatus(eventNotHandledErr) }
    let manager = Unmanaged<GlobalHotKeyManager>.fromOpaque(userData).takeUnretainedValue()
    return manager.handle(event: event)
}

/// 基于 Carbon `RegisterEventHotKey` 的全局热键，不需要辅助功能权限。
/// 每个实例使用独立的 signature，可以同时存在多组互不干扰的热键。
final class GlobalHotKeyManager {
    static let appSignature: OSType = 0x516B4F70     // "QkOp"：App 快捷键与速查面板
    static let overlaySignature: OSType = 0x516B4F76 // "QkOv"：浮层显示期间的临时按键

    private let signature: OSType
    private var eventHandler: EventHandlerRef?
    private var hotKeyRefs: [UUID: EventHotKeyRef] = [:]
    private var actions: [UInt32: () -> Void] = [:]
    private var releaseActions: [UInt32: () -> Void] = [:]
    private var numericIDs: [UUID: UInt32] = [:]
    private var nextNumericID: UInt32 = 1

    var isEmpty: Bool { hotKeyRefs.isEmpty }

    /// 正在派发的热键事件的时间戳（系统启动后的秒数，与 `ProcessInfo.systemUptime` 同基准）。
    /// 在 action / onRelease 回调中读取，用于判断事件发生的先后顺序。
    private(set) var currentEventTime: TimeInterval = 0

    init(signature: OSType = GlobalHotKeyManager.appSignature) {
        self.signature = signature
        var eventTypes = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased))
        ]
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            quickOpenHotKeyHandler,
            eventTypes.count,
            &eventTypes,
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
    func register(
        id: UUID,
        hotKey: HotKey,
        onRelease: (() -> Void)? = nil,
        action: @escaping () -> Void
    ) -> OSStatus {
        unregister(id: id)

        let numericID = nextNumericID
        nextNumericID &+= 1
        let identifier = EventHotKeyID(signature: signature, id: numericID)
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
            if let onRelease { releaseActions[numericID] = onRelease }
            numericIDs[id] = numericID
        }
        return status
    }

    func unregister(id: UUID) {
        if let existing = hotKeyRefs.removeValue(forKey: id) {
            UnregisterEventHotKey(existing)
        }
        if let numericID = numericIDs.removeValue(forKey: id) {
            actions.removeValue(forKey: numericID)
            releaseActions.removeValue(forKey: numericID)
        }
    }

    func unregisterAll() {
        hotKeyRefs.values.forEach { UnregisterEventHotKey($0) }
        hotKeyRefs.removeAll()
        actions.removeAll()
        releaseActions.removeAll()
        numericIDs.removeAll()
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
        // 不属于本实例的事件必须返回 eventNotHandledErr，让其他 handler 继续处理。
        guard status == noErr, identifier.signature == signature else { return OSStatus(eventNotHandledErr) }
        let isRelease = GetEventKind(event) == UInt32(kEventHotKeyReleased)
        let table = isRelease ? releaseActions : actions
        guard let action = table[identifier.id] else {
            return actions[identifier.id] == nil ? OSStatus(eventNotHandledErr) : noErr
        }
        // 派发到下一轮 runloop，避免在 Carbon 回调中修改热键注册表；保留事件发生的时间。
        let time = GetEventTime(event)
        DispatchQueue.main.async { [weak self] in
            self?.currentEventTime = time
            action()
        }
        return noErr
    }
}
