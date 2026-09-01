import AppKit
import TabListCore

/// Draws the selection itself so the highlight stays identical whether or not
/// the non-activating panel is key.
@MainActor
final class SwitcherRowBackgroundView: NSTableRowView {
    override func drawSelection(in dirtyRect: NSRect) {
        guard selectionHighlightStyle != .none else { return }
        let inset = bounds.insetBy(dx: 4, dy: 1)
        let path = NSBezierPath(
            roundedRect: inset,
            xRadius: PanelLayoutCalculator.rowCornerRadius,
            yRadius: PanelLayoutCalculator.rowCornerRadius
        )
        NSColor.controlAccentColor.withAlphaComponent(0.25).setFill()
        path.fill()
        if NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast {
            NSColor.controlAccentColor.setStroke()
            path.lineWidth = 2
            path.stroke()
        }
    }
}

/// One list row: application icon, application name, window title, state, and
/// a close control that appears for the selected or hovered row.
@MainActor
final class SwitcherRowView: NSTableCellView {
    static let identifier = NSUserInterfaceItemIdentifier("SwitcherRowView")

    var onClose: (() -> Void)?

    private let iconView = NSImageView()
    private let applicationLabel = NSTextField(labelWithString: "")
    private let titleLabel = NSTextField(labelWithString: "")
    private let stateLabel = NSTextField(labelWithString: "")
    private let closeButton = NSButton()
    private let closeProgress = NSProgressIndicator()

    private var isClosable = false
    private var isRowSelected = false
    private var isActionPending = false
    private var pointerInside = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        build()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(
            NSTrackingArea(
                rect: bounds,
                options: [.activeAlways, .mouseEnteredAndExited, .inVisibleRect],
                owner: self
            )
        )
    }

    override func mouseEntered(with event: NSEvent) {
        pointerInside = true
        updateCloseControls()
    }

    override func mouseExited(with event: NSEvent) {
        pointerInside = false
        updateCloseControls()
    }

    func configure(
        with item: SwitcherDisplayItem,
        position: Int,
        total: Int,
        isSelected: Bool,
        isActionPending: Bool
    ) {
        iconView.image = item.icon
        applicationLabel.stringValue = item.window.applicationName
        titleLabel.stringValue = item.title
        titleLabel.toolTip = item.title

        let states = item.stateDescriptions
        stateLabel.stringValue = states.joined(separator: " • ")
        stateLabel.isHidden = states.isEmpty

        isClosable = item.window.isClosable
        isRowSelected = isSelected
        self.isActionPending = isActionPending
        closeButton.toolTip = isClosable
            ? String(localized: "Close window")
            : String(localized: "This window cannot be closed by Tab‑List.")
        updateCloseControls()

        setAccessibilityElement(true)
        setAccessibilityRole(.row)
        setAccessibilityLabel(
            item.accessibilityLabel(position: position, total: total)
        )
        setAccessibilitySelected(isSelected)
    }

    private func build() {
        iconView.imageScaling = .scaleProportionallyDown
        iconView.translatesAutoresizingMaskIntoConstraints = false

        applicationLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        applicationLabel.lineBreakMode = .byTruncatingTail
        applicationLabel.translatesAutoresizingMaskIntoConstraints = false
        applicationLabel.setContentCompressionResistancePriority(
            .defaultHigh,
            for: .horizontal
        )

        titleLabel.font = .systemFont(ofSize: 13)
        titleLabel.textColor = .secondaryLabelColor
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.setContentCompressionResistancePriority(
            .defaultLow,
            for: .horizontal
        )

        stateLabel.font = .systemFont(ofSize: 11, weight: .medium)
        stateLabel.textColor = .tertiaryLabelColor
        stateLabel.lineBreakMode = .byTruncatingTail
        stateLabel.translatesAutoresizingMaskIntoConstraints = false
        stateLabel.setContentCompressionResistancePriority(
            .required,
            for: .horizontal
        )

        closeButton.image = NSImage(
            systemSymbolName: "xmark.circle.fill",
            accessibilityDescription: String(localized: "Close window")
        )
        closeButton.imagePosition = .imageOnly
        closeButton.isBordered = false
        closeButton.bezelStyle = .regularSquare
        closeButton.contentTintColor = .secondaryLabelColor
        closeButton.target = self
        closeButton.action = #selector(closePressed)
        closeButton.setAccessibilityLabel(String(localized: "Close window"))
        closeButton.translatesAutoresizingMaskIntoConstraints = false

        closeProgress.style = .spinning
        closeProgress.controlSize = .small
        closeProgress.isIndeterminate = true
        closeProgress.isHidden = true
        closeProgress.translatesAutoresizingMaskIntoConstraints = false

        for subview in [
            iconView,
            applicationLabel,
            titleLabel,
            stateLabel,
            closeButton,
            closeProgress,
        ] as [NSView] {
            addSubview(subview)
        }

        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(
                equalTo: leadingAnchor,
                constant: 14
            ),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 24),
            iconView.heightAnchor.constraint(equalToConstant: 24),

            applicationLabel.leadingAnchor.constraint(
                equalTo: iconView.trailingAnchor,
                constant: 10
            ),
            applicationLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            applicationLabel.widthAnchor.constraint(
                lessThanOrEqualToConstant: 170
            ),

            titleLabel.leadingAnchor.constraint(
                equalTo: applicationLabel.trailingAnchor,
                constant: 10
            ),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            titleLabel.trailingAnchor.constraint(
                lessThanOrEqualTo: stateLabel.leadingAnchor,
                constant: -8
            ),

            stateLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            stateLabel.trailingAnchor.constraint(
                equalTo: closeButton.leadingAnchor,
                constant: -8
            ),

            closeButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            closeButton.trailingAnchor.constraint(
                equalTo: trailingAnchor,
                constant: -12
            ),
            closeButton.widthAnchor.constraint(equalToConstant: 20),
            closeButton.heightAnchor.constraint(equalToConstant: 20),

            closeProgress.centerXAnchor.constraint(
                equalTo: closeButton.centerXAnchor
            ),
            closeProgress.centerYAnchor.constraint(
                equalTo: closeButton.centerYAnchor
            ),
            closeProgress.widthAnchor.constraint(equalToConstant: 16),
            closeProgress.heightAnchor.constraint(equalToConstant: 16),
        ])
    }

    private func updateCloseControls() {
        closeButton.isEnabled = isClosable && !isActionPending
        closeButton.isHidden = isActionPending
            || !(isRowSelected || pointerInside)
        closeProgress.isHidden = !isActionPending
        if isActionPending {
            closeProgress.startAnimation(nil)
        } else {
            closeProgress.stopAnimation(nil)
        }
    }

    @objc private func closePressed() {
        guard isClosable else {
            NSSound.beep()
            return
        }
        onClose?()
    }
}
