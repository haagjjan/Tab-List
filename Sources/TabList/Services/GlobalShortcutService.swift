@preconcurrency import AppKit
import Carbon.HIToolbox
import CoreGraphics
import Foundation
import TabListCore

public enum ShortcutInputCommand: Equatable, Sendable {
    case begin(reverse: Bool)
    case cycle(reverse: Bool)
    case commit
    case cancel
    case closeSelectedWindow
}

public enum GlobalShortcutError: Error, Equatable, Sendable {
    case invalidDefinition
    case registrationConflict(OSStatus)
    case eventTapUnavailable
    case eventTapStartupTimedOut
}

private final class ShortcutCallbackBox: @unchecked Sendable {
    let callback: @MainActor @Sendable (ShortcutInputCommand) -> Void

    init(
        callback: @escaping @MainActor @Sendable (ShortcutInputCommand) -> Void
    ) {
        self.callback = callback
    }

    func deliver(_ command: ShortcutInputCommand) {
        DispatchQueue.main.async { [callback] in
            MainActor.assumeIsolated {
                callback(command)
            }
        }
    }
}

private let carbonHotKeyHandler: EventHandlerUPP = {
    _, _, userData -> OSStatus in
    // The event tap is authoritative because it also suppresses native Cmd-Tab.
    // Carbon remains a fallback if macOS temporarily disables that tap.
    guard let userData else { return OSStatus(eventNotHandledErr) }
    let context = Unmanaged<EventTapContext>
        .fromOpaque(userData)
        .takeUnretainedValue()
    context.handleCarbonTrigger()
    return noErr
}

private final class EventTapContext: @unchecked Sendable {
    private let lock = NSLock()
    private let callbackBox: ShortcutCallbackBox

    private var shortcut: ShortcutDefinition
    private var sessionActive = false
    private var tap: CFMachPort?
    private var runLoop: CFRunLoop?
    private var runLoopSource: CFRunLoopSource?
    private var thread: Thread?
    private var startupCancelled = false

    init(
        shortcut: ShortcutDefinition,
        callbackBox: ShortcutCallbackBox
    ) {
        self.shortcut = shortcut
        self.callbackBox = callbackBox
    }

    func start() throws {
        let startup = DispatchSemaphore(value: 0)
        let startupLock = NSLock()
        nonisolated(unsafe) var startupSucceeded = false

        lock.lock()
        startupCancelled = false
        lock.unlock()

        let thread = Thread { [self] in
            let mask =
                CGEventMask(1 << CGEventType.keyDown.rawValue)
                | CGEventMask(1 << CGEventType.flagsChanged.rawValue)
                | CGEventMask(1 << CGEventType.tapDisabledByTimeout.rawValue)
                | CGEventMask(1 << CGEventType.tapDisabledByUserInput.rawValue)

            guard let createdTap = CGEvent.tapCreate(
                tap: .cgSessionEventTap,
                place: .headInsertEventTap,
                options: .defaultTap,
                eventsOfInterest: mask,
                callback: eventTapCallback,
                userInfo: Unmanaged.passUnretained(self).toOpaque()
            ) else {
                startup.signal()
                return
            }

            let source = CFMachPortCreateRunLoopSource(
                kCFAllocatorDefault,
                createdTap,
                0
            )
            let currentRunLoop = CFRunLoopGetCurrent()

            lock.lock()
            guard !startupCancelled else {
                lock.unlock()
                CFMachPortInvalidate(createdTap)
                startup.signal()
                return
            }
            tap = createdTap
            runLoop = currentRunLoop
            runLoopSource = source
            lock.unlock()

            CFRunLoopAddSource(currentRunLoop, source, .commonModes)
            CGEvent.tapEnable(tap: createdTap, enable: true)
            lock.lock()
            let wasCancelled = startupCancelled
            lock.unlock()
            if wasCancelled {
                CGEvent.tapEnable(tap: createdTap, enable: false)
                CFRunLoopRemoveSource(
                    currentRunLoop,
                    source,
                    .commonModes
                )
                CFMachPortInvalidate(createdTap)
                startup.signal()
                return
            }
            startupLock.lock()
            startupSucceeded = true
            startupLock.unlock()
            startup.signal()
            CFRunLoopRun()

            CGEvent.tapEnable(tap: createdTap, enable: false)
            CFRunLoopRemoveSource(currentRunLoop, source, .commonModes)
        }
        thread.name = "Tab-List keyboard event tap"
        thread.qualityOfService = .userInteractive

        lock.lock()
        self.thread = thread
        lock.unlock()
        thread.start()

        guard startup.wait(timeout: .now() + 2) == .success else {
            stop()
            throw GlobalShortcutError.eventTapStartupTimedOut
        }
        startupLock.lock()
        let succeeded = startupSucceeded
        startupLock.unlock()
        guard succeeded else {
            throw GlobalShortcutError.eventTapUnavailable
        }
    }

    func stop() {
        lock.lock()
        startupCancelled = true
        let localTap = tap
        let localRunLoop = runLoop
        tap = nil
        runLoop = nil
        runLoopSource = nil
        thread = nil
        sessionActive = false
        lock.unlock()

        if let localTap {
            CGEvent.tapEnable(tap: localTap, enable: false)
        }
        if let localRunLoop {
            CFRunLoopPerformBlock(localRunLoop, CFRunLoopMode.defaultMode.rawValue) {
                CFRunLoopStop(localRunLoop)
            }
            CFRunLoopWakeUp(localRunLoop)
        }
    }

    func updateShortcut(_ shortcut: ShortcutDefinition) {
        lock.lock()
        self.shortcut = shortcut
        lock.unlock()
    }

    func setSessionActive(_ active: Bool) {
        lock.lock()
        sessionActive = active
        lock.unlock()
    }

    func handleCarbonTrigger() {
        lock.lock()
        guard !sessionActive else {
            lock.unlock()
            return
        }
        sessionActive = true
        lock.unlock()
        let reverse = CGEventSource.flagsState(
            .combinedSessionState
        ).contains(.maskShift)
        callbackBox.deliver(.begin(reverse: reverse))
    }

    func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            lock.lock()
            let localTap = tap
            let wasActive = sessionActive
            sessionActive = false
            lock.unlock()
            if let localTap {
                CGEvent.tapEnable(tap: localTap, enable: true)
            }
            if wasActive {
                callbackBox.deliver(.cancel)
            }
            return Unmanaged.passUnretained(event)
        }

        lock.lock()
        let configuredShortcut = shortcut
        let active = sessionActive
        lock.unlock()

        if type == .flagsChanged {
            guard active else { return Unmanaged.passUnretained(event) }
            let held = modifiers(from: event.flags)
            let required = configuredShortcut.modifiers.subtracting(.shift)
            if !held.isSuperset(of: required) {
                setSessionActive(false)
                callbackBox.deliver(.commit)
            }
            return Unmanaged.passUnretained(event)
        }

        guard type == .keyDown else {
            return Unmanaged.passUnretained(event)
        }

        let keyCode = UInt16(
            event.getIntegerValueField(.keyboardEventKeycode)
        )
        let held = modifiers(from: event.flags)

        if active {
            switch keyCode {
            case UInt16(kVK_Escape):
                setSessionActive(false)
                callbackBox.deliver(.cancel)
                return nil
            case UInt16(kVK_Delete), UInt16(kVK_ForwardDelete):
                callbackBox.deliver(.closeSelectedWindow)
                return nil
            default:
                break
            }
        }

        guard keyCode == configuredShortcut.keyCode else {
            return Unmanaged.passUnretained(event)
        }

        let required = configuredShortcut.modifiers.subtracting(.shift)
        let heldNonShift = held.intersection(.nonShift)
        guard heldNonShift == required.intersection(.nonShift) else {
            return Unmanaged.passUnretained(event)
        }

        let reverse = held.contains(.shift)
        if active {
            callbackBox.deliver(.cycle(reverse: reverse))
        } else {
            setSessionActive(true)
            callbackBox.deliver(.begin(reverse: reverse))
        }
        return nil
    }

    private func modifiers(from flags: CGEventFlags) -> ShortcutModifiers {
        var result: ShortcutModifiers = []
        if flags.contains(.maskCommand) { result.insert(.command) }
        if flags.contains(.maskAlternate) { result.insert(.option) }
        if flags.contains(.maskControl) { result.insert(.control) }
        if flags.contains(.maskShift) { result.insert(.shift) }
        return result
    }
}

private let eventTapCallback: CGEventTapCallBack = {
    _, type, event, userInfo in
    guard let userInfo else {
        return Unmanaged.passUnretained(event)
    }
    let context = Unmanaged<EventTapContext>
        .fromOpaque(userInfo)
        .takeUnretainedValue()
    return context.handle(type: type, event: event)
}

/// Owns Carbon registration and the minimal active keyboard event filter.
@MainActor
public final class GlobalShortcutService {
    private static let signature: OSType = 0x544C5354 // "TLST"

    private var hotKey: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private var callbackBox: ShortcutCallbackBox?
    private var eventTapContext: EventTapContext?
    private(set) public var registeredShortcut: ShortcutDefinition?

    public init() {}

    isolated deinit {
        unregister()
    }

    /// Transactional replacement: a new Carbon hot key and event tap are built
    /// before the old registration is torn down.
    public func register(
        _ shortcut: ShortcutDefinition,
        handler: @escaping @MainActor @Sendable (ShortcutInputCommand) -> Void
    ) throws {
        guard ShortcutValidator.validate(shortcut).isValid,
              let keyCode = shortcut.keyCode else {
            throw GlobalShortcutError.invalidDefinition
        }

        let newBox = ShortcutCallbackBox(callback: handler)
        let newTapContext = EventTapContext(
            shortcut: shortcut,
            callbackBox: newBox
        )
        var newEventHandler: EventHandlerRef?
        var eventSpec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let installStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            carbonHotKeyHandler,
            1,
            &eventSpec,
            Unmanaged.passUnretained(newTapContext).toOpaque(),
            &newEventHandler
        )
        guard installStatus == noErr else {
            throw GlobalShortcutError.registrationConflict(installStatus)
        }

        var newHotKey: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(
            signature: Self.signature,
            id: 1
        )
        let registerStatus = RegisterEventHotKey(
            UInt32(keyCode),
            carbonModifiers(from: shortcut.modifiers),
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &newHotKey
        )
        guard registerStatus == noErr else {
            if let newEventHandler {
                RemoveEventHandler(newEventHandler)
            }
            throw GlobalShortcutError.registrationConflict(registerStatus)
        }

        do {
            try newTapContext.start()
        } catch {
            if let newHotKey { UnregisterEventHotKey(newHotKey) }
            if let newEventHandler { RemoveEventHandler(newEventHandler) }
            throw error
        }

        unregister()
        hotKey = newHotKey
        eventHandler = newEventHandler
        callbackBox = newBox
        eventTapContext = newTapContext
        registeredShortcut = shortcut
    }

    public func unregister() {
        eventTapContext?.stop()
        eventTapContext = nil

        if let hotKey {
            UnregisterEventHotKey(hotKey)
        }
        hotKey = nil

        if let eventHandler {
            RemoveEventHandler(eventHandler)
        }
        eventHandler = nil
        callbackBox = nil
        registeredShortcut = nil
    }

    public func setSessionActive(_ active: Bool) {
        eventTapContext?.setSessionActive(active)
    }

    /// Recreates the event tap after wake/unlock. If recreation fails, the
    /// registration remains removed so native keyboard handling fails closed.
    public func recoverAfterSystemTransition() throws {
        guard let shortcut = registeredShortcut,
              let callbackBox else {
            return
        }
        let callback = callbackBox.callback
        unregister()
        try register(shortcut, handler: callback)
    }

    private func carbonModifiers(
        from modifiers: ShortcutModifiers
    ) -> UInt32 {
        var result: UInt32 = 0
        if modifiers.contains(.command) { result |= UInt32(cmdKey) }
        if modifiers.contains(.option) { result |= UInt32(optionKey) }
        if modifiers.contains(.control) { result |= UInt32(controlKey) }
        // Shift is reserved for reverse cycling and is intentionally omitted.
        return result
    }
}
