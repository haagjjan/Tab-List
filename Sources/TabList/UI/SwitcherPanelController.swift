import AppKit
import CoreGraphics
import TabListCore

@MainActor
private final class CenteredCollectionViewFlowLayout:
    NSCollectionViewFlowLayout
{
    var itemCount = 0
    var columnCount = 1
    var centersIncompleteFinalRow = false

    override func layoutAttributesForElements(
        in rect: NSRect
    ) -> [NSCollectionViewLayoutAttributes] {
        super.layoutAttributesForElements(in: rect).map(adjusted)
    }

    override func layoutAttributesForItem(
        at indexPath: IndexPath
    ) -> NSCollectionViewLayoutAttributes? {
        super.layoutAttributesForItem(at: indexPath).map(adjusted)
    }

    private func adjusted(
        _ attributes: NSCollectionViewLayoutAttributes
    ) -> NSCollectionViewLayoutAttributes {
        guard centersIncompleteFinalRow,
              attributes.representedElementCategory == .item,
              columnCount > 1,
              itemCount > 0,
              let copy = attributes.copy()
                as? NSCollectionViewLayoutAttributes
        else {
            return attributes
        }
        let lastRowCount = itemCount % columnCount
        guard lastRowCount > 0,
              let indexPath = attributes.indexPath,
              indexPath.item >= itemCount - lastRowCount,
              let collectionView
        else {
            return attributes
        }
        let rowWidth = (CGFloat(lastRowCount) * itemSize.width)
            + (CGFloat(lastRowCount - 1) * minimumInteritemSpacing)
        let centeredOrigin = max(
            sectionInset.left,
            (collectionView.bounds.width - rowWidth) / 2
        )
        copy.frame.origin.x += centeredOrigin - sectionInset.left
        return copy
    }
}

@MainActor
final class SwitcherPanelController: NSWindowController, NSCollectionViewDelegate {
    var onActivate: ((WindowKey) -> Void)?
    var onClose: ((WindowKey) -> Void)?

    private let scrollView = NSScrollView()
    private let collectionView = NSCollectionView()
    private let flowLayout = CenteredCollectionViewFlowLayout()
    private let feedbackLabel = NSTextField(labelWithString: "")
    private var dataSource:
        NSCollectionViewDiffableDataSource<Int, WindowKey>!

    private var items: [SwitcherDisplayItem] = []
    private var itemsByKey: [WindowKey: SwitcherDisplayItem] = [:]
    private var selectedIndex: Int?
    private var pendingCloseKey: WindowKey?
    private var currentPresentation: PresentationMode = .thumbnails
    private var currentPanelSize: PanelSize = .auto
    private var currentTheme: ThemePreference = .system
    private var currentDisplayID: CGDirectDisplayID?
    private var currentLayoutMetrics: PanelLayoutMetrics?

    var backingScaleFactor: CGFloat {
        window?.backingScaleFactor ?? 2
    }

    var thumbnailCaptureTargetSize: CGSize? {
        currentLayoutMetrics?.previewViewportSize.map { viewport in
            CGSize(
                width: viewport.width * backingScaleFactor,
                height: viewport.height * backingScaleFactor
            )
        }
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

        applyAppearance()
        resizeAndCenter(panel)
        panel.orderFrontRegardless()
        applyDataSnapshot(reloading: changedKeys) { [weak self] in
            self?.updateSelection(
                scroll: true,
                movement: .stationary
            )
        }
    }

    func update(items: [SwitcherDisplayItem], selectedIndex: Int) {
        let changedKeys = replaceItems(items)
        self.selectedIndex = items.isEmpty
            ? nil
            : min(max(0, selectedIndex), items.count - 1)
        if items.isEmpty {
            hide()
        } else {
            if let panel = window {
                resizeAndCenter(panel)
            }
            applyDataSnapshot(reloading: changedKeys) { [weak self] in
                self?.updateSelection(
                    scroll: true,
                    movement: .stationary
                )
            }
        }
    }

    func select(index: Int) {
        guard items.indices.contains(index) else { return }
        let movement = selectionMovement(
            from: selectedIndex,
            to: index,
            itemCount: items.count
        )
        selectedIndex = index
        updateSelection(scroll: true, movement: movement)
    }

    func hide() {
        window?.orderOut(nil)
        items.removeAll(keepingCapacity: true)
        itemsByKey.removeAll(keepingCapacity: true)
        selectedIndex = nil
        pendingCloseKey = nil
        feedbackLabel.isHidden = true
        applyDataSnapshot(reloading: [])
    }

    private func configureContent() {
        guard let contentView = window?.contentView else { return }
        contentView.wantsLayer = true
        contentView.layer?.cornerRadius = 16
        contentView.layer?.masksToBounds = true

        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.automaticallyAdjustsContentInsets = false
        scrollView.contentInsets = NSEdgeInsets(
            top: 0,
            left: 0,
            bottom: 0,
            right: 0
        )
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        flowLayout.minimumInteritemSpacing = 12
        flowLayout.minimumLineSpacing = 12
        flowLayout.sectionInset = NSEdgeInsets(
            top: LayoutCalculator.outerPadding,
            left: LayoutCalculator.outerPadding,
            bottom: LayoutCalculator.outerPadding,
            right: LayoutCalculator.outerPadding
        )

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
                isActionPending: key == self.pendingCloseKey,
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
            scrollView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: contentView.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
            ,
            feedbackLabel.centerXAnchor.constraint(
                equalTo: contentView.centerXAnchor
            ),
            feedbackLabel.bottomAnchor.constraint(
                equalTo: contentView.bottomAnchor,
                constant: -10
            ),
            feedbackLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 360),
            feedbackLabel.heightAnchor.constraint(greaterThanOrEqualToConstant: 30)
        ])
    }

    func setPendingClose(_ key: WindowKey?) {
        let changed = Set([pendingCloseKey, key].compactMap { $0 })
        pendingCloseKey = key
        feedbackLabel.isHidden = true
        applyDataSnapshot(reloading: changed)
    }

    func showFeedback(_ message: String) {
        feedbackLabel.stringValue = "  \(message)  "
        feedbackLabel.isHidden = false
        feedbackLabel.superview?.addSubview(
            feedbackLabel,
            positioned: .above,
            relativeTo: scrollView
        )
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
        flowLayout.itemCount = items.count
        flowLayout.columnCount = metrics.columns
        flowLayout.centersIncompleteFinalRow =
            metrics.centersIncompleteFinalRow
        currentLayoutMetrics = metrics
        flowLayout.invalidateLayout()
        scrollView.hasVerticalScroller = metrics.isScrollable

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

    private func updateSelection(
        scroll: Bool,
        movement: SelectionMovement
    ) {
        collectionView.selectionIndexPaths = selectedIndex.map {
            [IndexPath(item: $0, section: 0)]
        } ?? []
        for case let cell as SwitcherCollectionItem in collectionView.visibleItems() {
            if let indexPath = collectionView.indexPath(for: cell) {
                cell.isSelected = indexPath.item == selectedIndex
            }
        }
        guard scroll, let selectedIndex else { return }
        revealSelection(at: selectedIndex, movement: movement)
    }

    private func revealSelection(
        at index: Int,
        movement: SelectionMovement
    ) {
        let indexPath = IndexPath(item: index, section: 0)
        collectionView.layoutSubtreeIfNeeded()
        guard let selectedFrame = flowLayout
            .layoutAttributesForItem(at: indexPath)?
            .frame
        else {
            collectionView.scrollToItems(
                at: [indexPath],
                scrollPosition: .centeredVertically
            )
            return
        }

        let alignment = SelectionScrollPlanner.alignment(
            selectedFrame: selectedFrame,
            visibleRect: collectionView.visibleRect,
            movement: movement
        )
        guard alignment == .centered else { return }
        collectionView.scrollToItems(
            at: [indexPath],
            scrollPosition: .centeredVertically
        )
    }

    private func selectionMovement(
        from previous: Int?,
        to next: Int,
        itemCount: Int
    ) -> SelectionMovement {
        guard let previous,
              previous != next,
              itemCount > 1
        else {
            return .stationary
        }
        if previous == itemCount - 1, next == 0 {
            return .forward
        }
        if previous == 0, next == itemCount - 1 {
            return .backward
        }
        return next > previous ? .forward : .backward
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

    private func applyDataSnapshot(
        reloading changedKeys: Set<WindowKey>,
        completion: (() -> Void)? = nil
    ) {
        guard let dataSource else {
            completion?()
            return
        }
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
        dataSource.apply(
            snapshot,
            animatingDifferences: false,
            completion: completion
        )
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

        // Alpha 2 uses a true semantic opaque surface. Avoiding a
        // visual-effect view keeps underlying content from competing with
        // titles and removes blur compositing from the lowest-resource mode.
        if let window {
            window.effectiveAppearance.performAsCurrentDrawingAppearance {
                window.contentView?.layer?.backgroundColor =
                    NSColor.windowBackgroundColor.cgColor
            }
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
