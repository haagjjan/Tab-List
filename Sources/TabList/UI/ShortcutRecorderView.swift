import AppKit
import Carbon.HIToolbox
import SwiftUI
import TabListCore

struct ShortcutRecorderView: NSViewRepresentable {
    let shortcut: ShortcutDefinition
    let onRecorded: (ShortcutDefinition) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onRecorded: onRecorded)
    }

    func makeNSView(context: Context) -> NSButton {
        let button = NSButton(title: displayString(shortcut), target: context.coordinator, action: #selector(Coordinator.startRecording(_:)))
        button.bezelStyle = .rounded
        button.font = .monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .medium)
        context.coordinator.button = button
        return button
    }

    func updateNSView(_ button: NSButton, context: Context) {
        guard !context.coordinator.isRecording else { return }
        button.title = displayString(shortcut)
        context.coordinator.onRecorded = onRecorded
    }

    private func displayString(_ shortcut: ShortcutDefinition) -> String {
        Self.displayString(shortcut)
    }

    static func displayString(_ shortcut: ShortcutDefinition) -> String {
        var value = ""
        if shortcut.modifiers.contains(.control) { value += "⌃" }
        if shortcut.modifiers.contains(.option) { value += "⌥" }
        if shortcut.modifiers.contains(.shift) { value += "⇧" }
        if shortcut.modifiers.contains(.command) { value += "⌘" }
        value += keyName(shortcut.keyCode)
        return value
    }

    private static func keyName(_ keyCode: UInt16?) -> String {
        guard let keyCode else { return "…" }
        switch keyCode {
        case 36: return "↩"
        case 48: return "⇥"
        case 49: return "Space"
        case 51: return "⌫"
        case 53: return "⎋"
        case 117: return "⌦"
        case 123: return "←"
        case 124: return "→"
        case 125: return "↓"
        case 126: return "↑"
        default:
            guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
                  let data = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
            else {
                return "#\(keyCode)"
            }
            let layoutData = unsafeBitCast(data, to: CFData.self)
            guard let layout = CFDataGetBytePtr(layoutData)?.withMemoryRebound(
                to: UCKeyboardLayout.self,
                capacity: 1,
                { $0 }
            ) else {
                return "#\(keyCode)"
            }
            var deadKeyState: UInt32 = 0
            var length = 0
            var characters = [UniChar](repeating: 0, count: 4)
            let status = UCKeyTranslate(
                layout,
                keyCode,
                UInt16(kUCKeyActionDisplay),
                0,
                UInt32(LMGetKbdType()),
                OptionBits(kUCKeyTranslateNoDeadKeysBit),
                &deadKeyState,
                characters.count,
                &length,
                &characters
            )
            guard status == noErr, length > 0 else { return "#\(keyCode)" }
            return String(utf16CodeUnits: characters, count: length).uppercased()
        }
    }

    @MainActor
    final class Coordinator: NSObject {
        var onRecorded: (ShortcutDefinition) -> Void
        weak var button: NSButton?
        var isRecording = false
        private var monitor: Any?

        init(onRecorded: @escaping (ShortcutDefinition) -> Void) {
            self.onRecorded = onRecorded
        }

        isolated deinit {
            if let monitor {
                NSEvent.removeMonitor(monitor)
            }
        }

        @objc func startRecording(_ sender: NSButton) {
            if isRecording {
                stopRecording()
                return
            }
            isRecording = true
            sender.title = String(localized: "Press shortcut…")
            sender.state = .on
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self, self.isRecording else { return event }
                if event.keyCode == 53, event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty {
                    self.stopRecording()
                    return nil
                }
                let definition = ShortcutDefinition(
                    keyCode: event.keyCode,
                    modifiers: Self.modifiers(from: event.modifierFlags)
                )
                self.onRecorded(definition)
                self.stopRecording(displaying: definition)
                return nil
            }
        }

        private func stopRecording(displaying shortcut: ShortcutDefinition? = nil) {
            if let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
            isRecording = false
            button?.state = .off
            if let shortcut {
                button?.title = ShortcutRecorderView.displayString(shortcut)
            }
        }

        private static func modifiers(from flags: NSEvent.ModifierFlags) -> ShortcutModifiers {
            var modifiers: ShortcutModifiers = []
            if flags.contains(.command) { modifiers.insert(.command) }
            if flags.contains(.option) { modifiers.insert(.option) }
            if flags.contains(.control) { modifiers.insert(.control) }
            if flags.contains(.shift) { modifiers.insert(.shift) }
            return modifiers
        }
    }
}
