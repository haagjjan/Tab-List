import AppKit
import TabListCore

@MainActor
private final class SwitcherItemRootView: NSView {
    var pressHandler: (() -> Void)?

    override func accessibilityPerformPress() -> Bool {
        guard let pressHandler else { return false }
        pressHandler()
        return true
    }
}

@MainActor
final class SwitcherCollectionItem: NSCollectionViewItem {
    static let identifier = NSUserInterfaceItemIdentifier("SwitcherCollectionItem")

    private let selectionView = NSView()
    private let previewImageView = NSImageView()
    private let appNameLabel = NSTextField(labelWithString: "")
    private let titleLabel = NSTextField(labelWithString: "")
    private let stateLabel = NSTextField(labelWithString: "")
    private let closeButton = NSButton()

    private var representedSwitcherItem: SwitcherDisplayItem?
    private var presentation: PresentationMode = .thumbnails
    private var activateHandler: (() -> Void)?
    private var closeHandler: (() -> Void)?
    private var trackingArea: NSTrackingArea?
    private var pointerInside = false

    override func loadView() {
        view = SwitcherItemRootView()
        view.wantsLayer = true
        view.layer?.cornerRadius = 12

        selectionView.wantsLayer = true
        selectionView.layer?.cornerRadius = 12
        selectionView.layer?.borderWidth = 0
        selectionView.translatesAutoresizingMaskIntoConstraints = false

        previewImageView.imageScaling = .scaleProportionallyUpOrDown
        previewImageView.imageAlignment = .alignCenter
        previewImageView.wantsLayer = true
        previewImageView.layer?.cornerRadius = 8
        previewImageView.layer?.masksToBounds = true
        previewImageView.translatesAutoresizingMaskIntoConstraints = false

        appNameLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        appNameLabel.lineBreakMode = .byTruncatingTail
        appNameLabel.translatesAutoresizingMaskIntoConstraints = false

        titleLabel.font = .systemFont(ofSize: 12)
        titleLabel.textColor = .secondaryLabelColor
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.maximumNumberOfLines = 1
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        stateLabel.font = .systemFont(ofSize: 10, weight: .medium)
        stateLabel.textColor = .tertiaryLabelColor
        stateLabel.lineBreakMode = .byTruncatingTail
        stateLabel.translatesAutoresizingMaskIntoConstraints = false

        closeButton.image = NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: String(localized: "Close window"))
        closeButton.imagePosition = .imageOnly
        closeButton.isBordered = false
        closeButton.bezelStyle = .regularSquare
        closeButton.contentTintColor = .secondaryLabelColor
        closeButton.toolTip = String(localized: "Close window")
        closeButton.target = self
        closeButton.action = #selector(closePressed)
        closeButton.setAccessibilityLabel(String(localized: "Close window"))
        closeButton.translatesAutoresizingMaskIntoConstraints = false

        let clickRecognizer = NSClickGestureRecognizer(
            target: self,
            action: #selector(itemPressed(_:))
        )
        clickRecognizer.delaysPrimaryMouseButtonEvents = false
        view.addGestureRecognizer(clickRecognizer)

        view.addSubview(selectionView)
        selectionView.addSubview(previewImageView)
        selectionView.addSubview(appNameLabel)
        selectionView.addSubview(titleLabel)
        selectionView.addSubview(stateLabel)
        selectionView.addSubview(closeButton)

        NSLayoutConstraint.activate([
            selectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            selectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            selectionView.topAnchor.constraint(equalTo: view.topAnchor),
            selectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            closeButton.widthAnchor.constraint(equalToConstant: 24),
            closeButton.heightAnchor.constraint(equalToConstant: 24),
            closeButton.topAnchor.constraint(equalTo: selectionView.topAnchor, constant: 6),
            closeButton.trailingAnchor.constraint(equalTo: selectionView.trailingAnchor, constant: -6)
        ])

        let area = NSTrackingArea(
            rect: view.bounds,
            options: [.activeAlways, .mouseEnteredAndExited, .inVisibleRect],
            owner: self
        )
        view.addTrackingArea(area)
        trackingArea = area
    }

    override var isSelected: Bool {
        didSet {
            updateSelectionAppearance()
            updateCloseButtonVisibility()
        }
    }

    override func mouseEntered(with event: NSEvent) {
        pointerInside = true
        updateCloseButtonVisibility()
    }

    override func mouseExited(with event: NSEvent) {
        pointerInside = false
        updateCloseButtonVisibility()
    }

    func configure(
        with item: SwitcherDisplayItem,
        presentation: PresentationMode,
        position: Int,
        total: Int,
        activateHandler: @escaping () -> Void,
        closeHandler: @escaping () -> Void
    ) {
        representedSwitcherItem = item
        self.presentation = presentation
        self.activateHandler = activateHandler
        self.closeHandler = closeHandler

        appNameLabel.stringValue = item.window.applicationName
        let title = item.window.windowTitle.isEmpty ? String(localized: "Untitled window") : item.window.windowTitle
        titleLabel.stringValue = title
        titleLabel.toolTip = title

        var states: [String] = []
        if item.window.isMinimized { states.append(String(localized: "Minimized")) }
        if item.window.isFullscreen { states.append(String(localized: "Full Screen")) }
        stateLabel.stringValue = states.joined(separator: " • ")
        stateLabel.isHidden = states.isEmpty

        switch presentation {
        case .thumbnails:
            if let thumbnail = item.thumbnail {
                previewImageView.image = NSImage(
                    cgImage: thumbnail,
                    size: NSSize(width: thumbnail.width, height: thumbnail.height)
                )
            } else {
                previewImageView.image = item.icon
            }
            previewImageView.imageScaling = item.thumbnail == nil ? .scaleProportionallyDown : .scaleProportionallyUpOrDown
        case .appIcons:
            previewImageView.image = item.icon
            previewImageView.imageScaling = .scaleProportionallyDown
        case .titles:
            previewImageView.image = item.icon
            previewImageView.imageScaling = .scaleProportionallyDown
        }

        closeButton.isEnabled = item.window.isClosable
        closeButton.toolTip = item.window.isClosable
            ? String(localized: "Close window")
            : String(localized: "This window cannot be closed by Tab‑List.")
        closeButton.isHidden = true
        view.setAccessibilityElement(true)
        view.setAccessibilityRole(.button)
        view.setAccessibilityLabel(
            item.accessibilityLabel(position: position, total: total)
        )
        view.setAccessibilityHelp(String(localized: "Activate this window"))
        (view as? SwitcherItemRootView)?.pressHandler = activateHandler

        rebuildConstraints()
        updateSelectionAppearance()
    }

    private func rebuildConstraints() {
        NSLayoutConstraint.deactivate(selectionView.constraints.filter { constraint in
            [previewImageView, appNameLabel, titleLabel, stateLabel].contains { view in
                constraint.firstItem as AnyObject? === view || constraint.secondItem as AnyObject? === view
            }
        })

        switch presentation {
        case .thumbnails:
            NSLayoutConstraint.activate([
                previewImageView.leadingAnchor.constraint(equalTo: selectionView.leadingAnchor, constant: 8),
                previewImageView.trailingAnchor.constraint(equalTo: selectionView.trailingAnchor, constant: -8),
                previewImageView.topAnchor.constraint(equalTo: selectionView.topAnchor, constant: 8),
                previewImageView.bottomAnchor.constraint(equalTo: appNameLabel.topAnchor, constant: -7),

                appNameLabel.leadingAnchor.constraint(equalTo: selectionView.leadingAnchor, constant: 10),
                appNameLabel.trailingAnchor.constraint(lessThanOrEqualTo: closeButton.leadingAnchor, constant: -4),
                appNameLabel.bottomAnchor.constraint(equalTo: titleLabel.topAnchor, constant: -1),

                titleLabel.leadingAnchor.constraint(equalTo: appNameLabel.leadingAnchor),
                titleLabel.trailingAnchor.constraint(equalTo: selectionView.trailingAnchor, constant: -10),
                titleLabel.bottomAnchor.constraint(equalTo: selectionView.bottomAnchor, constant: -8),

                stateLabel.leadingAnchor.constraint(equalTo: previewImageView.leadingAnchor, constant: 6),
                stateLabel.topAnchor.constraint(equalTo: previewImageView.topAnchor, constant: 6)
            ])
        case .appIcons:
            NSLayoutConstraint.activate([
                previewImageView.centerXAnchor.constraint(equalTo: selectionView.centerXAnchor),
                previewImageView.topAnchor.constraint(equalTo: selectionView.topAnchor, constant: 14),
                previewImageView.widthAnchor.constraint(equalTo: selectionView.widthAnchor, multiplier: 0.48),
                previewImageView.heightAnchor.constraint(equalTo: previewImageView.widthAnchor),

                appNameLabel.leadingAnchor.constraint(equalTo: selectionView.leadingAnchor, constant: 8),
                appNameLabel.trailingAnchor.constraint(equalTo: selectionView.trailingAnchor, constant: -8),
                appNameLabel.topAnchor.constraint(equalTo: previewImageView.bottomAnchor, constant: 8),

                titleLabel.leadingAnchor.constraint(equalTo: appNameLabel.leadingAnchor),
                titleLabel.trailingAnchor.constraint(equalTo: appNameLabel.trailingAnchor),
                titleLabel.topAnchor.constraint(equalTo: appNameLabel.bottomAnchor, constant: 2),
                titleLabel.bottomAnchor.constraint(lessThanOrEqualTo: stateLabel.topAnchor, constant: -1),

                stateLabel.leadingAnchor.constraint(equalTo: appNameLabel.leadingAnchor),
                stateLabel.trailingAnchor.constraint(equalTo: appNameLabel.trailingAnchor),
                stateLabel.bottomAnchor.constraint(equalTo: selectionView.bottomAnchor, constant: -6)
            ])
        case .titles:
            NSLayoutConstraint.activate([
                previewImageView.leadingAnchor.constraint(equalTo: selectionView.leadingAnchor, constant: 10),
                previewImageView.centerYAnchor.constraint(equalTo: selectionView.centerYAnchor),
                previewImageView.widthAnchor.constraint(equalToConstant: 28),
                previewImageView.heightAnchor.constraint(equalToConstant: 28),

                appNameLabel.leadingAnchor.constraint(equalTo: previewImageView.trailingAnchor, constant: 10),
                appNameLabel.centerYAnchor.constraint(equalTo: selectionView.centerYAnchor),
                appNameLabel.widthAnchor.constraint(equalTo: selectionView.widthAnchor, multiplier: 0.28),

                titleLabel.leadingAnchor.constraint(equalTo: appNameLabel.trailingAnchor, constant: 8),
                titleLabel.centerYAnchor.constraint(equalTo: selectionView.centerYAnchor),
                titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: stateLabel.leadingAnchor, constant: -8),

                stateLabel.centerYAnchor.constraint(equalTo: selectionView.centerYAnchor),
                stateLabel.trailingAnchor.constraint(equalTo: closeButton.leadingAnchor, constant: -8)
            ])
        }
    }

    private func updateSelectionAppearance() {
        guard let layer = selectionView.layer else { return }
        if isSelected {
            layer.borderColor = NSColor.controlAccentColor.cgColor
            layer.borderWidth =
                NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
                ? 4
                : 3
            layer.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.13).cgColor
        } else {
            layer.borderWidth =
                NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
                ? 1
                : 0
            layer.borderColor = NSColor.separatorColor.cgColor
            layer.backgroundColor = NSColor.labelColor.withAlphaComponent(0.045).cgColor
        }
        view.setAccessibilitySelected(isSelected)
    }

    private func updateCloseButtonVisibility() {
        closeButton.isHidden = !(isSelected || pointerInside)
    }

    @objc private func closePressed() {
        guard representedSwitcherItem?.window.isClosable == true else {
            NSSound.beep()
            return
        }
        closeHandler?()
    }

    @objc private func itemPressed(_ recognizer: NSClickGestureRecognizer) {
        let locationInCloseButton = recognizer.location(in: closeButton)
        guard !closeButton.bounds.contains(locationInCloseButton) else {
            return
        }
        activateHandler?()
    }
}
