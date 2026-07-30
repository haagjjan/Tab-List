import AppKit
import CoreGraphics
import TabListCore

@MainActor
final class SwitcherPanelController: NSWindowController, NSCollectionViewDelegate {
    var onActivate: ((WindowKey) -> Void)?
    var onClose: ((WindowKey) -> Void)?

    private let materialView = NSVisualEffectView()
    private let scrollView = NSScrollView()
    private let collectionView = NSCollectionView()
    private let flowLayout = NSCollectionViewFlowLayout()
    private var dataSource:
        NSCollectionViewDiffableDataSource<Int, WindowKey>!

    private var items: [SwitcherDisplayItem] = []
    private var itemsByKey: [WindowKey: SwitcherDisplayItem] = [:]
    private var selectedIndex: Int?
    private var currentPresentation: PresentationMode = .thumbnails
    private var currentPanelSize: PanelSize = .auto
    private var currentTheme: ThemePreference = .system
    private var currentDisplayID: CGDirectDisplayID?
    private var opacity: Double = 0.88

    var backingScaleFactor: CGFloat {
        window?.backingScaleFactor ?? 2
    }

    var visibleWindowKeys: [WindowKey] {
        collectionView.visibleItems()
            .compactMap { collectionView.indexPath(for: $0) }
            .sorted { $0.item < $1.item }
            .compactMap { indexPath in
                items.indices.contains(indexPath.item)
                    ? items[indexPath.item].window.id
                    : nil
            }
    }

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
        opacity: Double,
        displayID: CGDirectDisplayID?
    ) {
        guard !items.isEmpty, let panel = window else { return }
        let cellStyleChanged =
            currentPresentation != presentation || currentTheme != theme
        let changedKeys = replaceItems(
            items,
            forceReload: cellStyleChanged
        )
        self.selectedIndex = min(max(0, selectedIndex), items.count - 1)
        currentPresentation = presentation
        currentPanelSize = panelSize
        currentTheme = theme
        currentDisplayID = displayID
        self.opacity = min(max(opacity, 0.70), 1.0)

        applyAppearance()
        applyDataSnapshot(reloading: changedKeys)
        resizeAndCenter(panel)
        updateSelection(scroll: false)
        panel.orderFrontRegardless()
        updateSelection(scroll: true)
    }

    func update(items: [SwitcherDisplayItem], selectedIndex: Int) {
        let changedKeys = replaceItems(items)
        self.selectedIndex = items.isEmpty ? nil : min(max(0, selectedIndex), items.count - 1)
        applyDataSnapshot(reloading: changedKeys)
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
        itemsByKey.removeAll(keepingCapacity: true)
        selectedIndex = nil
        applyDataSnapshot(reloading: [])
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
        collectionView.delegate = self
        collectionView.isSelectable = true
        collectionView.allowsMultipleSelection = false
        collectionView.backgroundColors = [.clear]
        collectionView.register(
            SwitcherCollectionItem.self,
            forItemWithIdentifier: SwitcherCollectionItem.identifier
        )
        dataSource = NSCollectionViewDiffableDataSource<Int, WindowKey>(
            collectionView: collectionView
        ) { [weak self] collectionView, indexPath, key in
            guard let self,
                  let item = self.itemsByKey[key],
                  let cell = collectionView.makeItem(
                      withIdentifier: SwitcherCollectionItem.identifier,
                      for: indexPath
                  ) as? SwitcherCollectionItem else {
                return NSCollectionViewItem()
            }
            cell.configure(
                with: item,
                presentation: self.currentPresentation,
                position: indexPath.item + 1,
                total: self.items.count,
                activateHandler: { [weak self] in
                    self?.onActivate?(key)
                },
                closeHandler: { [weak self] in
                    self?.onClose?(key)
                }
            )
            cell.isSelected = indexPath.item == self.selectedIndex
            return cell
        }
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
        let screen = Self.screen(for: currentDisplayID)
            ?? NSScreen.main
            ?? NSScreen.screens.first
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

    private func replaceItems(
        _ newItems: [SwitcherDisplayItem],
        forceReload: Bool = false
    ) -> Set<WindowKey> {
        let changedKeys = SwitcherDisplayReloadPlanner.keys(
            previous: items,
            next: newItems,
            forceReload: forceReload
        )
        let next = newItems.reduce(
            into: [WindowKey: SwitcherDisplayItem]()
        ) { result, item in
            result[item.window.id] = item
        }
        items = newItems
        itemsByKey = next
        return changedKeys
    }

    private func applyDataSnapshot(reloading changedKeys: Set<WindowKey>) {
        guard let dataSource else { return }
        let identifiers = items.map(\.window.id)
        let previous = Set(dataSource.snapshot().itemIdentifiers)
        var snapshot = NSDiffableDataSourceSnapshot<Int, WindowKey>()
        snapshot.appendSections([0])
        snapshot.appendItems(identifiers, toSection: 0)
        let changedRetained = identifiers.filter {
            previous.contains($0) && changedKeys.contains($0)
        }
        if !changedRetained.isEmpty {
            snapshot.reloadItems(changedRetained)
        }
        dataSource.apply(snapshot, animatingDifferences: false)
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
