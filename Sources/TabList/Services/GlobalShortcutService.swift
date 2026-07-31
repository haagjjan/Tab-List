@preconcurrency import AppKit
import Carbon.HIToolbox
import CoreGraphics
import Foundation
import TabListCore

public enum ShortcutInputCommand: Equatable, Sendable {
    case begin(reverse: Bool)
    case cycle(reverse: Bool, isRepeat: Bool)
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

struct ShortcutEventOutcome: Equatable, Sendable {
    let command: ShortcutInputCommand?
    let consumesEvent: Bool
    let sessionActive: Bool
}

enum HoldCycleTiming {
    static func repeatInterval(
        systemInterval: TimeInterval,
        speed: Double
    ) -> TimeInterval {
        let safeSystemInterval = max(0.02, systemInterval)
        let safeSpeed = min(max(speed.isFinite ? speed : 1, 0.5), 2.0)
        return max(0.02, safeSystemInterval / safeSpeed)
    }
}

/// Pure event interpretation shared by the live event tap and regression
/// tests. Shift is a direction modifier; the configured trigger key still
/// performs the step.
enum ShortcutEventInterpreter {
    static func consumesKeyUp(
        keyCode: UInt16,
        shortcut: ShortcutDefinition,
        reverseControl: ReverseControlDefinition,
        sessionActive: Bool
    ) -> Bool {
        guard sessionActive else { return false }
        if Int(keyCode) == kVK_Delete || Int(keyCode) == kVK_ForwardDelete {
            return true
        }
        if keyCode == shortcut.keyCode { return true }
        if case let .key(reverseKeyCode) = reverseControl {
            return keyCode == reverseKeyCode
        }
        return reverseControl == .shiftOnly && Int(keyCode) == kVK_Shift
    }

    static func keyDown(
        keyCode: UInt16,
        heldModifiers: ShortcutModifiers,
        shortcut: ShortcutDefinition,
        sessionActive: Bool,
        isRepeat: Bool = false
    ) -> ShortcutEventOutcome {
        if sessionActive {
            switch Int(keyCode) {
            case kVK_Escape:
                return ShortcutEventOutcome(
                    command: .cancel,
                    consumesEvent: true,
                    sessionActive: false
                )
            case kVK_Delete, kVK_ForwardDelete:
                return ShortcutEventOutcome(
                    command: .closeSelectedWindow,
                    consumesEvent: true,
                    sessionActive: true
                )
            default:
                break
            }
        }

        guard keyCode == shortcut.keyCode else {
            return ShortcutEventOutcome(
                command: nil,
                consumesEvent: false,
                sessionActive: sessionActive
            )
        }

        let required = shortcut.modifiers.subtracting(.shift)
        let heldNonShift = heldModifiers.intersection(.nonShift)
        guard heldNonShift == required.intersection(.nonShift) else {
            return ShortcutEventOutcome(
                command: nil,
                consumesEvent: false,
                sessionActive: sessionActive
            )
        }

        let reverse = heldModifiers.contains(.shift)
        return ShortcutEventOutcome(
            command: sessionActive
                ? .cycle(reverse: reverse, isRepeat: isRepeat)
                : .begin(reverse: reverse),
            consumesEvent: true,
            sessionActive: true
        )
    }

    static func modifiersChanged(
        heldModifiers: ShortcutModifiers,
        shortcut: ShortcutDefinition,
        sessionActive: Bool
    ) -> ShortcutEventOutcome {
        guard sessionActive else {
            return ShortcutEventOutcome(
                command: nil,
                consumesEvent: false,
                sessionActive: false
            )
        }
        let required = shortcut.modifiers.subtracting(.shift)
        guard heldModifiers.isSuperset(of: required) else {
            return ShortcutEventOutcome(
                command: .commit,
                consumesEvent: false,
                sessionActive: false
            )
        }
        return ShortcutEventOutcome(
            command: nil,
            consumesEvent: false,
            sessionActive: true
        )
    }
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
    private var reverseControl: ReverseControlDefinition
    private var holdCycleSpeed: Double
    private let systemInitialRepeatDelay: TimeInterval
    private let systemRepeatInterval: TimeInterval
    private var sessionActive = false
    private var previousModifiers: ShortcutModifiers = []
    private var pressedCycleKey: UInt16?
    private var repeatDirectionIsReverse = false
    private var repeatTimer: DispatchSourceTimer?
    private var tap: CFMachPort?
    private var runLoop: CFRunLoop?
    private var runLoopSource: CFRunLoopSource?
    private var thread: Thread?
    private var startupCancelled = false

    init(
        shortcut: ShortcutDefinition,
        reverseControl: ReverseControlDefinition,
        holdCycleSpeed: Double,
        systemInitialRepeatDelay: TimeInterval,
        systemRepeatInterval: TimeInterval,
        callbackBox: ShortcutCallbackBox
    ) {
        self.shortcut = shortcut
        self.reverseControl = reverseControl
        self.holdCycleSpeed = holdCycleSpeed
        self.systemInitialRepeatDelay = systemInitialRepeatDelay
        self.systemRepeatInterval = systemRepeatInterval
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
                | CGEventMask(1 << CGEventType.keyUp.rawValue)
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
        stopRepeatLocked()
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

    func updateSessionControls(
        reverseControl: ReverseControlDefinition,
        holdCycleSpeed: Double
    ) {
        lock.lock()
        self.reverseControl = reverseControl
        self.holdCycleSpeed = min(max(holdCycleSpeed, 0.5), 2.0)
        lock.unlock()
    }

    func setSessionActive(_ active: Bool) {
        lock.lock()
        sessionActive = active
        if !active {
            stopRepeatLocked()
        }
        lock.unlock()
    }

    func handleCarbonTrigger() {
        lock.lock()
        guard !sessionActive else {
            lock.unlock()
            return
        }
        sessionActive = true
        let configuredReverseControl = reverseControl
        lock.unlock()
        // Carbon is only a recovery path when the event tap is unavailable.
        // Shift changes the initial direction only for Shift+forward mode;
        // custom and Shift-only bindings are handled explicitly while a
        // session is active and must not alter the forward trigger.
        let reverse = configuredReverseControl == .shiftWithForwardKey
            && CGEventSource.flagsState(
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
            stopRepeatLocked()
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
        let configuredReverseControl = reverseControl
        let active = sessionActive
        let priorModifiers = previousModifiers
        let heldModifiers = modifiers(from: event.flags)
        previousModifiers = heldModifiers
        lock.unlock()

        if type == .flagsChanged {
            var consumedShiftOnlyTransition = false
            if active,
               configuredReverseControl == .shiftOnly {
                let shiftWasHeld = priorModifiers.contains(.shift)
                let shiftIsHeld = heldModifiers.contains(.shift)
                if shiftIsHeld != shiftWasHeld {
                    consumedShiftOnlyTransition = true
                    if shiftIsHeld {
                        callbackBox.deliver(
                            .cycle(reverse: true, isRepeat: false)
                        )
                        beginRepeat(
                            keyCode: UInt16(kVK_Shift),
                            reverse: true
                        )
                    } else {
                        endRepeat(keyCode: UInt16(kVK_Shift))
                    }
                }
            }
            let outcome = ShortcutEventInterpreter.modifiersChanged(
                heldModifiers: heldModifiers,
                shortcut: configuredShortcut,
                sessionActive: active
            )
            if outcome.sessionActive != active {
                setSessionActive(outcome.sessionActive)
            }
            if let command = outcome.command {
                callbackBox.deliver(command)
            }
            return consumedShiftOnlyTransition
                ? nil
                : Unmanaged.passUnretained(event)
        }

        guard type == .keyDown || type == .keyUp else {
            return Unmanaged.passUnretained(event)
        }

        let keyCode = UInt16(
            event.getIntegerValueField(.keyboardEventKeycode)
        )
        if type == .keyUp {
            let cycleRelease = isCycleKey(
                keyCode,
                shortcut: configuredShortcut,
                reverseControl: configuredReverseControl
            )
            if cycleRelease {
                endRepeat(keyCode: keyCode)
            }
            return ShortcutEventInterpreter.consumesKeyUp(
                keyCode: keyCode,
                shortcut: configuredShortcut,
                reverseControl: configuredReverseControl,
                sessionActive: active
            )
                ? nil
                : Unmanaged.passUnretained(event)
        }

        let isAutorepeat = event.getIntegerValueField(
            .keyboardEventAutorepeat
        ) != 0
        if active,
           case let .key(reverseKeyCode) = configuredReverseControl,
           keyCode == reverseKeyCode {
            if !isAutorepeat {
                callbackBox.deliver(
                    .cycle(reverse: true, isRepeat: false)
                )
                beginRepeat(keyCode: keyCode, reverse: true)
            }
            return nil
        }

        let effectiveModifiers = configuredReverseControl
            == .shiftWithForwardKey
            ? heldModifiers
            : heldModifiers.subtracting(.shift)
        let outcome = ShortcutEventInterpreter.keyDown(
            keyCode: keyCode,
            heldModifiers: effectiveModifiers,
            shortcut: configuredShortcut,
            sessionActive: active,
            isRepeat: false
        )
        if outcome.sessionActive != active {
            setSessionActive(outcome.sessionActive)
        }
        if let command = outcome.command, !isAutorepeat {
            callbackBox.deliver(command)
            switch command {
            case let .begin(reverse), let .cycle(reverse, _):
                beginRepeat(keyCode: keyCode, reverse: reverse)
            case .commit, .cancel, .closeSelectedWindow:
                break
            }
        }
        return outcome.consumesEvent
            ? nil
            : Unmanaged.passUnretained(event)
    }

    private func isCycleKey(
        _ keyCode: UInt16,
        shortcut: ShortcutDefinition,
        reverseControl: ReverseControlDefinition
    ) -> Bool {
        if keyCode == shortcut.keyCode { return true }
        if case let .key(reverseKeyCode) = reverseControl {
            return keyCode == reverseKeyCode
        }
        return reverseControl == .shiftOnly && Int(keyCode) == kVK_Shift
    }

    private func beginRepeat(keyCode: UInt16, reverse: Bool) {
        lock.lock()
        stopRepeatLocked()
        pressedCycleKey = keyCode
        repeatDirectionIsReverse = reverse
        let speed = holdCycleSpeed
        let timer = DispatchSource.makeTimerSource(
            queue: DispatchQueue.global(qos: .userInteractive)
        )
        timer.schedule(
            deadline: .now() + systemInitialRepeatDelay,
            repeating: HoldCycleTiming.repeatInterval(
                systemInterval: systemRepeatInterval,
                speed: speed
            ),
            leeway: .milliseconds(2)
        )
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            self.lock.lock()
            let shouldDeliver = self.sessionActive
                && self.pressedCycleKey == keyCode
            let reverse = self.repeatDirectionIsReverse
            self.lock.unlock()
            if shouldDeliver {
                self.callbackBox.deliver(
                    .cycle(reverse: reverse, isRepeat: true)
                )
            }
        }
        repeatTimer = timer
        timer.resume()
        lock.unlock()
    }

    private func endRepeat(keyCode: UInt16) {
        lock.lock()
        if pressedCycleKey == keyCode {
            stopRepeatLocked()
        }
        lock.unlock()
    }

    private func stopRepeatLocked() {
        repeatTimer?.setEventHandler {}
        repeatTimer?.cancel()
        repeatTimer = nil
        pressedCycleKey = nil
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
    private var reverseControl: ReverseControlDefinition =
        .shiftWithForwardKey
    private var holdCycleSpeed = 1.0

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
            reverseControl: reverseControl,
            holdCycleSpeed: holdCycleSpeed,
            systemInitialRepeatDelay: NSEvent.keyRepeatDelay,
            systemRepeatInterval: NSEvent.keyRepeatInterval,
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

    public func configureSessionControls(
        reverseControl: ReverseControlDefinition,
        holdCycleSpeed: Double
    ) {
        self.reverseControl = reverseControl
        self.holdCycleSpeed = min(max(holdCycleSpeed, 0.5), 2.0)
        eventTapContext?.updateSessionControls(
            reverseControl: reverseControl,
            holdCycleSpeed: self.holdCycleSpeed
        )
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
