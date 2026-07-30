import AppKit
import TabListCore

@MainActor
final class SwitcherPanelController: NSWindowController, NSCollectionViewDataSource, NSCollectionViewDelegate {
    var onActivate: ((WindowKey) -> Void)?
    var onClose: ((WindowKey) -> Void)?

    private let materialView = NSVisualEffectView()
    private let scrollView = NSScrollView()
    private let collectionView = NSCollectionView()
    private let flowLayout = NSCollectionViewFlowLayout()

    private var items: [SwitcherDisplayItem] = []
    private var selectedIndex: Int?
    private var currentPresentation: PresentationMode = .thumbnails
    private var currentPanelSize: PanelSize = .auto
    private var currentTheme: ThemePreference = .system
    private var opacity: Double = 0.88

    init() {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 540),
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
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
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
        presentation: PresentationMode,
        panelSize: PanelSize,
        theme: ThemePreference,
        opacity: Double
    ) {
        guard !items.isEmpty, let panel = window else { return }
        self.items = items
        self.selectedIndex = min(max(0, selectedIndex), items.count - 1)
        currentPresentation = presentation
        currentPanelSize = panelSize
        currentTheme = theme
        self.opacity = min(max(opacity, 0.70), 1.0)

        applyAppearance()
        collectionView.reloadData()
        resizeAndCenter(panel)
        updateSelection(scroll: false)
        panel.orderFrontRegardless()
        updateSelection(scroll: true)
    }

    func update(items: [SwitcherDisplayItem], selectedIndex: Int) {
        self.items = items
        self.selectedIndex = items.isEmpty ? nil : min(max(0, selectedIndex), items.count - 1)
        collectionView.reloadData()
        if items.isEmpty {
            hide()
        } else {
            if let panel = window {
                resizeAndCenter(panel)
            }
            updateSelection(scroll: true)
        }
    }

    func select(index: Int) {
        guard items.indices.contains(index) else { return }
        selectedIndex = index
        updateSelection(scroll: true)
    }

    func hide() {
        window?.orderOut(nil)
        items.removeAll(keepingCapacity: true)
        selectedIndex = nil
        collectionView.reloadData()
    }

    func numberOfSections(in collectionView: NSCollectionView) -> Int { 1 }

    func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int {
        items.count
    }

    func collectionView(
        _ collectionView: NSCollectionView,
        itemForRepresentedObjectAt indexPath: IndexPath
    ) -> NSCollectionViewItem {
        guard
            let cell = collectionView.makeItem(
                withIdentifier: SwitcherCollectionItem.identifier,
                for: indexPath
            ) as? SwitcherCollectionItem
        else {
            return NSCollectionViewItem()
        }

        let item = items[indexPath.item]
        cell.configure(
            with: item,
            presentation: currentPresentation,
            position: indexPath.item + 1,
            total: items.count,
            activateHandler: { [weak self] in
                self?.onActivate?(item.window.id)
            },
            closeHandler: { [weak self] in
                self?.onClose?(item.window.id)
            }
        )
        cell.isSelected = indexPath.item == selectedIndex
        return cell
    }

    private func configureContent() {
        guard let contentView = window?.contentView else { return }
        contentView.wantsLayer = true
        contentView.layer?.cornerRadius = 16
        contentView.layer?.masksToBounds = true

        materialView.material = .hudWindow
        materialView.blendingMode = .behindWindow
        materialView.state = .active
        materialView.translatesAutoresizingMaskIntoConstraints = false

        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.contentInsets = NSEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        flowLayout.minimumInteritemSpacing = 12
        flowLayout.minimumLineSpacing = 12
        flowLayout.sectionInset = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)

        collectionView.collectionViewLayout = flowLayout
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.isSelectable = true
        collectionView.allowsMultipleSelection = false
        collectionView.backgroundColors = [.clear]
        collectionView.register(
            SwitcherCollectionItem.self,
            forItemWithIdentifier: SwitcherCollectionItem.identifier
        )
        collectionView.setAccessibilityRole(.list)
        scrollView.documentView = collectionView

        contentView.addSubview(materialView)
        contentView.addSubview(scrollView)

        NSLayoutConstraint.activate([
            materialView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            materialView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            materialView.topAnchor.constraint(equalTo: contentView.topAnchor),
            materialView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

            scrollView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: contentView.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        ])
    }

    private func resizeAndCenter(_ panel: NSWindow) {
        let screen = Self.pointerScreen() ?? NSScreen.main ?? NSScreen.screens.first
        guard let screen else { return }
        let visibleFrame = screen.visibleFrame
        let metrics = LayoutCalculator.metrics(
            preset: currentPanelSize,
            presentation: currentPresentation,
            displayVisibleFrame: visibleFrame,
            itemCount: items.count
        )
        flowLayout.itemSize = NSSize(
            width: metrics.itemSize.width,
            height: metrics.itemSize.height
        )
        flowLayout.invalidateLayout()

        let origin = NSPoint(
            x: visibleFrame.midX - metrics.panelSize.width / 2,
            y: visibleFrame.midY - metrics.panelSize.height / 2
        )
        panel.setFrame(
            NSRect(
                origin: origin,
                size: NSSize(
                    width: metrics.panelSize.width,
                    height: metrics.panelSize.height
                )
            ),
            display: true
        )
    }

    private func updateSelection(scroll: Bool) {
        collectionView.selectionIndexPaths = selectedIndex.map { [IndexPath(item: $0, section: 0)] } ?? []
        for case let cell as SwitcherCollectionItem in collectionView.visibleItems() {
            if let indexPath = collectionView.indexPath(for: cell) {
                cell.isSelected = indexPath.item == selectedIndex
            }
        }
        if scroll, let selectedIndex {
            collectionView.scrollToItems(
                at: [IndexPath(item: selectedIndex, section: 0)],
                scrollPosition: .nearestVerticalEdge
            )
        }
    }

    private func applyAppearance() {
        window?.alphaValue = 1
        switch currentTheme {
        case .system:
            window?.appearance = nil
        case .light:
            window?.appearance = NSAppearance(named: .aqua)
        case .dark:
            window?.appearance = NSAppearance(named: .darkAqua)
        }

        let reduceTransparency =
            NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
        if reduceTransparency {
            materialView.isHidden = true
            window?.contentView?.layer?.backgroundColor =
                NSColor.windowBackgroundColor.cgColor
        } else {
            materialView.isHidden = false
            materialView.material = .hudWindow
            materialView.alphaValue = opacity
            window?.contentView?.layer?.backgroundColor = NSColor.clear.cgColor
        }
        window?.animationBehavior =
            NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            ? .none
            : .utilityWindow
    }

    private static func pointerScreen() -> NSScreen? {
        let pointer = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(pointer, $0.frame, false) }
    }
}
