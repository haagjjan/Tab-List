import AppKit
import SwiftUI

@MainActor
final class OnboardingWindowController: NSWindowController {
    init(model: OnboardingViewModel) {
        let hostingController = NSHostingController(rootView: OnboardingView(model: model))
        let window = NSWindow(contentViewController: hostingController)
        window.title = String(localized: "Welcome to Tab‑List")
        window.styleMask = [.titled, .closable]
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.center()
        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show() {
        NSApp.activate()
        window?.center()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }
}
