import AppKit
import CoreGraphics
import TabListCore

@MainActor
private final class SwitcherTableView: NSTableView {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override var acceptsFirstResponder: Bool { false }
}

/// The switcher list. Rows are driven entirely by the session coordinator; the
/// panel itself never activates the application or takes key focus.
@MainActor
final class SwitcherPanelController: NSWindowController,
    NSTableViewDataSource,
    NSTableViewDelegate
{
    var onActivate: ((WindowKey) -> Void)?
    var onClose: ((WindowKey) -> Void)?

    private let scrollView = NSScrollView()
    private let tableView = SwitcherTableView()
    private let feedbackLabel = NSTextField(labelWithString: "")

    private var items: [SwitcherDisplayItem] = []
    private var selectedIndex: Int?
    private var pendingCloseKey: WindowKey?
    private var currentTheme: ThemePreference = .system
    private var currentDisplayID: CGDirectDisplayID?

    init() {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 240),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        panel.level = .popUpMenu
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isMovable = false
        panel.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .transient,
            .ignoresCycle,
        ]
        panel.animationBehavior = .utilityWindow
        panel.isReleasedWhenClosed = false
        super.init(window: panel)
        configureContent()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show(
        items: [SwitcherDisplayItem],
        selectedIndex: Int,
        theme: ThemePreference,
        displayID: CGDirectDisplayID?
    ) {
        guard !items.isEmpty, let panel = window else { return }
        currentTheme = theme
        currentDisplayID = displayID
        self.items = items
        self.selectedIndex = min(max(0, selectedIndex), items.count - 1)

        applyAppearance()
        resizeAndCenter(panel)
        tableView.reloadData()
        panel.orderFrontRegardless()
        applySelection(movement: .stationary)
    }

    func update(items: [SwitcherDisplayItem], selectedIndex: Int) {
        guard !items.isEmpty else {
            hide()
            return
        }
        let changed = SwitcherDisplayReloadPlanner.changedRows(
            previous: self.items,
            next: items
        )
        let countChanged = self.items.count != items.count
        self.items = items
        self.selectedIndex = min(max(0, selectedIndex), items.count - 1)

        if let panel = window {
            resizeAndCenter(panel)
        }
        if countChanged {
            tableView.reloadData()
        } else if !changed.isEmpty {
            tableView.reloadData(
                forRowIndexes: changed,
                columnIndexes: IndexSet(integer: 0)
            )
        }
        applySelection(movement: .stationary)
    }

    func select(index: Int) {
        guard items.indices.contains(index) else { return }
        let movement = Self.movement(
            from: selectedIndex,
            to: index,
            itemCount: items.count
        )
        selectedIndex = index
        applySelection(movement: movement)
    }

    func setPendingClose(_ key: WindowKey?) {
        let affected = IndexSet(
            items.indices.filter {
                items[$0].window.id == key
                    || items[$0].window.id == pendingCloseKey
            }
        )
        pendingCloseKey = key
        feedbackLabel.isHidden = true
        guard !affected.isEmpty else { return }
        tableView.reloadData(
            forRowIndexes: affected,
            columnIndexes: IndexSet(integer: 0)
        )
        applySelection(movement: .stationary)
    }

    func showFeedback(_ message: String) {
        feedbackLabel.stringValue = "  \(message)  "
        feedbackLabel.isHidden = false
    }

    func hide() {
        window?.orderOut(nil)
        items.removeAll(keepingCapacity: true)
        selectedIndex = nil
        pendingCloseKey = nil
        feedbackLabel.isHidden = true
        tableView.reloadData()
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        items.count
    }

    func tableView(
        _ tableView: NSTableView,
        rowViewForRow row: Int
    ) -> NSTableRowView? {
        SwitcherRowBackgroundView()
    }

    func tableView(
        _ tableView: NSTableView,
        viewFor tableColumn: NSTableColumn?,
        row: Int
    ) -> NSView? {
        guard items.indices.contains(row) else { return nil }
        let cell = tableView.makeView(
            withIdentifier: SwitcherRowView.identifier,
            owner: self
        ) as? SwitcherRowView ?? {
            let created = SwitcherRowView()
            created.identifier = SwitcherRowView.identifier
            return created
        }()

        let item = items[row]
        cell.onClose = { [weak self] in
            self?.onClose?(item.window.id)
        }
        cell.configure(
            with: item,
            position: row + 1,
            total: items.count,
            isSelected: row == selectedIndex,
            isActionPending: item.window.id == pendingCloseKey
        )
        return cell
    }

    func tableView(
        _ tableView: NSTableView,
        shouldSelectRow row: Int
    ) -> Bool {
        items.indices.contains(row)
    }

    private func configureContent() {
        guard let contentView = window?.contentView else { return }
        contentView.wantsLayer = true
        contentView.layer?.cornerRadius = PanelLayoutCalculator.cornerRadius
        contentView.layer?.masksToBounds = true

        let column = NSTableColumn(identifier: .init("window"))
        column.resizingMask = .autoresizingMask
        column.minWidth = 200
        column.width = PanelLayoutCalculator.maximumWidth
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.autoresizingMask = [.width]
        tableView.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        tableView.backgroundColor = .clear
        tableView.rowHeight = PanelLayoutCalculator.rowHeight
        tableView.intercellSpacing = .zero
        tableView.style = .plain
        tableView.selectionHighlightStyle = .regular
        tableView.allowsEmptySelection = true
        tableView.allowsMultipleSelection = false
        tableView.usesAutomaticRowHeights = false
        tableView.dataSource = self
        tableView.delegate = self
        tableView.target = self
        tableView.action = #selector(rowClicked)
        tableView.setAccessibilityRole(.table)
        tableView.setAccessibilityLabel(String(localized: "Open windows"))

        scrollView.documentView = tableView
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.automaticallyAdjustsContentInsets = false
        scrollView.contentInsets = NSEdgeInsets(
            top: PanelLayoutCalculator.outerPadding,
            left: 0,
            bottom: PanelLayoutCalculator.outerPadding,
            right: 0
        )
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(scrollView)

        feedbackLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        feedbackLabel.textColor = .white
        feedbackLabel.alignment = .center
        feedbackLabel.wantsLayer = true
        feedbackLabel.layer?.cornerRadius = 8
        feedbackLabel.layer?.backgroundColor = NSColor.systemRed
            .withAlphaComponent(0.92).cgColor
        feedbackLabel.isHidden = true
        feedbackLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(feedbackLabel)

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(
                equalTo: contentView.leadingAnchor
            ),
            scrollView.trailingAnchor.constraint(
                equalTo: contentView.trailingAnchor
            ),
            scrollView.topAnchor.constraint(equalTo: contentView.topAnchor),
            scrollView.bottomAnchor.constraint(
                equalTo: contentView.bottomAnchor
            ),

            feedbackLabel.centerXAnchor.constraint(
                equalTo: contentView.centerXAnchor
            ),
            feedbackLabel.bottomAnchor.constraint(
                equalTo: contentView.bottomAnchor,
                constant: -8
            ),
            feedbackLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 380),
            feedbackLabel.heightAnchor.constraint(
                greaterThanOrEqualToConstant: 28
            ),
        ])
    }

    @objc private func rowClicked() {
        let row = tableView.clickedRow
        guard items.indices.contains(row) else { return }
        onActivate?(items[row].window.id)
    }

    private func applySelection(movement: SelectionMovement) {
        guard let selectedIndex, items.indices.contains(selectedIndex) else {
            tableView.deselectAll(nil)
            return
        }
        tableView.selectRowIndexes(
            IndexSet(integer: selectedIndex),
            byExtendingSelection: false
        )
        revealSelection(at: selectedIndex, movement: movement)
    }

    private func revealSelection(at index: Int, movement: SelectionMovement) {
        tableView.layoutSubtreeIfNeeded()
        let rowFrame = tableView.rect(ofRow: index)
        let visibleRect = tableView.visibleRect
        let alignment = SelectionScrollPlanner.alignment(
            selectedFrame: rowFrame,
            visibleRect: visibleRect,
            movement: movement
        )
        guard alignment == .centered else { return }
        let targetY = rowFrame.midY - (visibleRect.height / 2)
        let maximumY = max(0, tableView.bounds.height - visibleRect.height)
        tableView.scroll(
            NSPoint(x: 0, y: min(max(0, targetY), maximumY))
        )
    }

    private func resizeAndCenter(_ panel: NSWindow) {
        let screen = Self.screen(for: currentDisplayID)
            ?? NSScreen.main
            ?? NSScreen.screens.first
        guard let screen else { return }
        let visibleFrame = screen.visibleFrame
        let layout = PanelLayoutCalculator.layout(
            displayVisibleFrame: visibleFrame,
            itemCount: items.count
        )
        scrollView.hasVerticalScroller = layout.isScrollable

        let size = NSSize(
            width: layout.panelSize.width,
            height: layout.panelSize.height
        )
        panel.setFrame(
            NSRect(
                origin: NSPoint(
                    x: (visibleFrame.midX - size.width / 2).rounded(),
                    y: (visibleFrame.midY - size.height / 2).rounded()
                ),
                size: size
            ),
            display: true
        )
    }

    private func applyAppearance() {
        guard let window else { return }
        window.alphaValue = 1
        switch currentTheme {
        case .system:
            window.appearance = nil
        case .light:
            window.appearance = NSAppearance(named: .aqua)
        case .dark:
            window.appearance = NSAppearance(named: .darkAqua)
        }
        window.effectiveAppearance.performAsCurrentDrawingAppearance {
            window.contentView?.layer?.backgroundColor =
                NSColor.windowBackgroundColor.cgColor
        }
        window.animationBehavior =
            NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            ? .none
            : .utilityWindow
    }

    /// Direction of a selection change, including the wrap-around cases the
    /// scroll planner needs in order to recentre instead of nudging.
    static func movement(
        from previous: Int?,
        to next: Int,
        itemCount: Int
    ) -> SelectionMovement {
        guard let previous, previous != next, itemCount > 1 else {
            return .stationary
        }
        if previous == itemCount - 1, next == 0 { return .forward }
        if previous == 0, next == itemCount - 1 { return .backward }
        return next > previous ? .forward : .backward
    }

    private static func screen(
        for displayID: CGDirectDisplayID?
    ) -> NSScreen? {
        guard let displayID else { return nil }
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        return NSScreen.screens.first { screen in
            guard let number = screen.deviceDescription[key] as? NSNumber else {
                return false
            }
            return CGDirectDisplayID(number.uint32Value) == displayID
        }
    }
}

enum SwitcherDisplayReloadPlanner {
    /// Rows whose rendered content changed between two equally sized lists.
    static func changedRows(
        previous: [SwitcherDisplayItem],
        next: [SwitcherDisplayItem]
    ) -> IndexSet {
        guard previous.count == next.count else {
            return IndexSet(next.indices)
        }
        return IndexSet(
            next.indices.filter {
                !next[$0].hasSameRenderedContent(as: previous[$0])
            }
        )
    }
}
