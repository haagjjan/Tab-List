import AppKit

private final class FlippedFixtureDocumentView: NSView {
    override var isFlipped: Bool { true }
}

@MainActor
final class FixtureController: NSObject, NSWindowDelegate {
    private var controlWindowController: NSWindowController?
    private var fixtureWindows: [NSWindowController] = []
    private var serial = 0

    func start() {
        let control = makeControlWindow()
        controlWindowController = NSWindowController(window: control)
        controlWindowController?.showWindow(nil)

        if let requestedCount = Self.requestedWindowCount {
            createBulkStandardWindows(count: max(0, requestedCount - 1))
            return
        }
        createStandardWindow()
        createStandardWindow()
        createUntitledWindow()
    }

    private static var requestedWindowCount: Int? {
        let environmentValue = ProcessInfo.processInfo.environment[
            "TABLIST_FIXTURE_WINDOW_COUNT"
        ]
        let argumentValue = ProcessInfo.processInfo.arguments
            .first { $0.hasPrefix("--fixture-window-count=") }?
            .split(separator: "=", maxSplits: 1)
            .last
            .map(String.init)
        guard let raw = environmentValue ?? argumentValue,
              let count = Int(raw),
              (2...100).contains(count) else {
            return nil
        }
        return count
    }

    private func makeControlWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 120, y: 80, width: 500, height: 780),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Tab-List Window Fixture Controls"
        window.setFrameAutosaveName("WindowFixtureControls")
        window.contentView = makeControls()
        window.center()
        return window
    }

    private func makeControls() -> NSView {
        let title = NSTextField(labelWithString: "Window scenarios")
        title.font = .preferredFont(forTextStyle: .title1)

        let explanation = NSTextField(
            wrappingLabelWithString: "Create predictable window types for manual Tab-List compatibility checks. Closing a fixture window never quits this app."
        )
        explanation.textColor = .secondaryLabelColor

        let buttons: [(String, Selector)] = [
            ("New standard window", #selector(addStandardWindow)),
            ("New untitled window", #selector(addUntitledWindow)),
            ("New utility panel", #selector(addUtilityPanel)),
            ("New unclosable window", #selector(addUnclosableWindow)),
            ("New unsaved document", #selector(addUnsavedDocument)),
            ("New native tab group", #selector(addNativeTabGroup)),
            ("New identical-title pair", #selector(addIdenticalTitlePair)),
            ("New very-long-title window", #selector(addVeryLongTitleWindow)),
            ("Show modal sheet", #selector(showModalSheet)),
            ("Minimize a standard window", #selector(minimizeStandardWindow)),
            ("Toggle fullscreen on a standard window", #selector(toggleFullscreen)),
            ("Retitle a standard window", #selector(retitleStandardWindow)),
            ("Move and resize a standard window", #selector(moveAndResizeStandardWindow)),
            ("Create 10 standard windows", #selector(addTenStandardWindows)),
            ("Create 50 standard windows", #selector(addFiftyStandardWindows)),
            ("Create 100 standard windows", #selector(addOneHundredStandardWindows)),
            ("Hide fixture application", #selector(hideFixtureApplication)),
            ("Block fixture main thread for 8 seconds", #selector(blockMainThread))
        ]

        let buttonViews = buttons.map { title, selector in
            let button = NSButton(title: title, target: self, action: selector)
            button.bezelStyle = .rounded
            button.setAccessibilityIdentifier("fixture.\(title.lowercased().replacingOccurrences(of: " ", with: "-"))")
            return button
        }

        let stack = NSStackView(views: [title, explanation] + buttonViews)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false

        let document = FlippedFixtureDocumentView(
            frame: NSRect(x: 0, y: 0, width: 480, height: 980)
        )
        document.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(
                equalTo: document.leadingAnchor,
                constant: 24
            ),
            stack.trailingAnchor.constraint(
                equalTo: document.trailingAnchor,
                constant: -24
            ),
            stack.topAnchor.constraint(
                equalTo: document.topAnchor,
                constant: 24
            ),
        ])

        let scrollView = NSScrollView()
        scrollView.documentView = document
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        return scrollView
    }

    @objc private func addStandardWindow() {
        createStandardWindow()
    }

    @objc private func addUntitledWindow() {
        createUntitledWindow()
    }

    @objc private func addUtilityPanel() {
        serial += 1
        let panel = NSPanel(
            contentRect: NSRect(x: 220, y: 220, width: 320, height: 180),
            styleMask: [.titled, .closable, .utilityWindow, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.title = "Utility Palette \(serial)"
        panel.isFloatingPanel = true
        panel.contentView = makeFixtureContent(
            heading: "Utility panel",
            detail: "Expected default behavior: excluded from the switcher."
        )
        retainAndShow(panel)
    }

    @objc private func addUnclosableWindow() {
        serial += 1
        let window = NSWindow(
            contentRect: NSRect(x: 280, y: 280, width: 440, height: 240),
            styleMask: [.titled, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Unclosable Window \(serial)"
        window.contentView = makeFixtureContent(
            heading: "Unclosable standard window",
            detail: "The Tab-List close affordance should be disabled for this item."
        )
        retainAndShow(window)
    }

    @objc private func addUnsavedDocument() {
        serial += 1
        let window = makeStandardWindow(
            title: "Unsaved Document \(serial)"
        )
        window.identifier = NSUserInterfaceItemIdentifier(
            "fixture.unsaved-document"
        )
        window.isDocumentEdited = true
        retainAndShow(window)
    }

    @objc private func addNativeTabGroup() {
        let first = makeStandardWindow(title: "Native Tab A")
        let second = makeStandardWindow(title: "Native Tab B")
        first.addTabbedWindow(second, ordered: .above)
        retainAndShow(first)
        retainAndShow(second)
        first.makeKeyAndOrderFront(nil)
    }

    @objc private func addIdenticalTitlePair() {
        serial += 2
        retainAndShow(makeStandardWindow(title: "Identical Fixture Title"))
        retainAndShow(makeStandardWindow(title: "Identical Fixture Title"))
    }

    @objc private func addVeryLongTitleWindow() {
        serial += 1
        retainAndShow(
            makeStandardWindow(
                title: "Very Long Fixture Window Title — "
                    + String(repeating: "0123456789 ", count: 24)
            )
        )
    }

    @objc private func showModalSheet() {
        guard let parent = controlWindowController?.window else {
            return
        }

        let sheet = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 160),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        sheet.title = "Unsaved Changes"

        let dismiss = NSButton(title: "Dismiss", target: nil, action: nil)
        dismiss.bezelStyle = .rounded
        dismiss.target = self
        dismiss.action = #selector(dismissSheet(_:))

        let stack = NSStackView(views: [
            NSTextField(wrappingLabelWithString: "This sheet simulates an application asking for confirmation after a close action."),
            dismiss
        ])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        sheet.contentView?.addSubview(stack)
        if let contentView = sheet.contentView {
            NSLayoutConstraint.activate([
                stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
                stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),
                stack.centerYAnchor.constraint(equalTo: contentView.centerYAnchor)
            ])
        }

        parent.beginSheet(sheet)
    }

    @objc private func dismissSheet(_ sender: NSButton) {
        guard
            let sheet = sender.window,
            let parent = sheet.sheetParent
        else {
            return
        }
        parent.endSheet(sheet)
    }

    @objc private func discardAndClose(_ sender: NSButton) {
        guard
            let sheet = sender.window,
            let parent = sheet.sheetParent
        else {
            return
        }
        parent.endSheet(sheet)
        parent.isDocumentEdited = false
        parent.identifier = nil
        parent.performClose(nil)
    }

    @objc private func minimizeStandardWindow() {
        fixtureWindows
            .compactMap(\.window)
            .first(where: { !$0.isMiniaturized && !($0 is NSPanel) })?
            .miniaturize(nil)
    }

    @objc private func toggleFullscreen() {
        fixtureWindows
            .compactMap(\.window)
            .first(where: { !($0 is NSPanel) })?
            .toggleFullScreen(nil)
    }

    @objc private func retitleStandardWindow() {
        serial += 1
        fixtureWindows
            .compactMap(\.window)
            .first(where: { !($0 is NSPanel) })?
            .title = "Retitled Fixture Window \(serial)"
    }

    @objc private func moveAndResizeStandardWindow() {
        guard let window = fixtureWindows
            .compactMap(\.window)
            .first(where: { !($0 is NSPanel) }) else {
            return
        }
        var frame = window.frame
        frame.origin.x += 37
        frame.origin.y += 29
        frame.size.width = max(360, frame.size.width - 43)
        frame.size.height = max(220, frame.size.height - 31)
        window.setFrame(frame, display: true, animate: false)
    }

    @objc private func addTenStandardWindows() {
        createBulkStandardWindows(count: 10)
    }

    @objc private func addFiftyStandardWindows() {
        createBulkStandardWindows(count: 50)
    }

    @objc private func addOneHundredStandardWindows() {
        createBulkStandardWindows(count: 100)
    }

    @objc private func hideFixtureApplication() {
        NSApp.hide(nil)
    }

    @objc private func blockMainThread() {
        Thread.sleep(forTimeInterval: 8)
    }

    private func createStandardWindow() {
        serial += 1
        retainAndShow(makeStandardWindow(title: "Standard Window \(serial)"))
    }

    private func createBulkStandardWindows(count: Int) {
        for _ in 0..<min(max(count, 0), 100) {
            createStandardWindow()
        }
    }

    private func createUntitledWindow() {
        serial += 1
        let window = makeStandardWindow(title: "")
        window.setAccessibilityIdentifier("fixture.untitled-window-\(serial)")
        retainAndShow(window)
    }

    private func makeStandardWindow(title: String) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 180 + serial * 14, y: 180 + serial * 14, width: 520, height: 320),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = title
        window.delegate = self
        window.contentView = makeFixtureContent(
            heading: title.isEmpty ? "Untitled standard window" : title,
            detail: "PID \(ProcessInfo.processInfo.processIdentifier) · use this window to test selection, activation, minimizing, fullscreen, and close behavior."
        )
        return window
    }

    private func makeFixtureContent(heading: String, detail: String) -> NSView {
        let headingField = NSTextField(labelWithString: heading)
        headingField.font = .preferredFont(forTextStyle: .title2)

        let detailField = NSTextField(wrappingLabelWithString: detail)
        detailField.textColor = .secondaryLabelColor

        let stack = NSStackView(views: [headingField, detailField])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false

        let container = NSView()
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: container.topAnchor, constant: 24)
        ])
        return container
    }

    private func retainAndShow(_ window: NSWindow) {
        let controller = NSWindowController(window: window)
        fixtureWindows.append(controller)
        controller.showWindow(nil)
    }

    func windowWillClose(_ notification: Notification) {
        fixtureWindows.removeAll { $0.window === notification.object as? NSWindow }
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard sender.identifier?.rawValue == "fixture.unsaved-document"
        else {
            return true
        }
        guard sender.attachedSheet == nil else { return false }

        let sheet = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 170),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        sheet.title = "Save changes?"

        let message = NSTextField(
            wrappingLabelWithString:
                "The document has unsaved changes. Tab‑List should dismiss "
                + "its panel and activate this application."
        )
        let keepOpen = NSButton(
            title: "Keep Open",
            target: self,
            action: #selector(dismissSheet(_:))
        )
        let discard = NSButton(
            title: "Discard and Close",
            target: self,
            action: #selector(discardAndClose(_:))
        )
        discard.keyEquivalent = "\r"

        let buttons = NSStackView(views: [keepOpen, discard])
        buttons.orientation = .horizontal
        buttons.spacing = 10
        let stack = NSStackView(views: [message, buttons])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 18
        stack.translatesAutoresizingMaskIntoConstraints = false
        sheet.contentView?.addSubview(stack)
        if let contentView = sheet.contentView {
            NSLayoutConstraint.activate([
                stack.leadingAnchor.constraint(
                    equalTo: contentView.leadingAnchor,
                    constant: 24
                ),
                stack.trailingAnchor.constraint(
                    equalTo: contentView.trailingAnchor,
                    constant: -24
                ),
                stack.centerYAnchor.constraint(
                    equalTo: contentView.centerYAnchor
                ),
            ])
        }
        sender.beginSheet(sheet)
        return false
    }
}
