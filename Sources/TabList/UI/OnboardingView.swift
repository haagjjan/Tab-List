import SwiftUI

@MainActor
final class OnboardingViewModel: ObservableObject {
    enum Step: Int, CaseIterable {
        case welcome
        case accessibility
        case thumbnails
        case ready
    }

    @Published var step: Step = .welcome
    @Published var accessibilityGranted = false
    @Published var screenRecordingGranted = false
    @Published var screenRecordingRestartRequired = false
    @Published var isRequesting = false

    var onRequestAccessibility: (() -> Void)?
    var onOpenAccessibilitySettings: (() -> Void)?
    var onRequestScreenRecording: (() -> Void)?
    var onContinueWithoutThumbnails: (() -> Void)?
    var onQuitAndReopen: (() -> Void)?
    var onReady: (() -> Void)?
    var onFinish: (() -> Void)?

    func advance() {
        guard let next = Step(rawValue: step.rawValue + 1) else { return }
        if next == .ready {
            showReady()
        } else {
            step = next
        }
    }

    func showReady() {
        let isEnteringReady = step != .ready
        step = .ready
        screenRecordingRestartRequired = false
        if isEnteringReady {
            onReady?()
        }
    }
}

struct OnboardingView: View {
    @ObservedObject var model: OnboardingViewModel

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(32)
            Divider()
            footer
        }
        .frame(width: 620, height: 460)
        .background(.background)
        .accessibilityIdentifier("onboarding.root")
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "rectangle.3.group")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text("Welcome to Tab‑List")
                    .font(.title2.bold())
                    .accessibilityIdentifier("onboarding.title")
                Text("Switch between windows, not just applications.")
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(24)
    }

    @ViewBuilder
    private var content: some View {
        switch model.step {
        case .welcome:
            VStack(alignment: .leading, spacing: 20) {
                permissionExplanation(
                    symbol: "keyboard",
                    title: "A faster window switcher",
                    body: "Hold Command and press Tab to move through every eligible macOS window. Release Command to activate the selected window."
                )
                permissionExplanation(
                    symbol: "hand.raised",
                    title: "Private by design",
                    body: "Window information and previews stay on this Mac. Tab‑List has no analytics and never uploads window titles or screenshots."
                )
                Spacer()
            }
        case .accessibility:
            VStack(alignment: .leading, spacing: 20) {
                permissionExplanation(
                    symbol: "accessibility",
                    title: "Allow Accessibility",
                    body: "This permission lets Tab‑List observe the shortcut and activate or close the window you choose."
                )
                permissionStatus(
                    granted: model.accessibilityGranted,
                    grantedText: "Accessibility is enabled",
                    missingText: "Accessibility is required"
                )
                HStack {
                    Button("Request Permission") {
                        model.onRequestAccessibility?()
                    }
                    .buttonStyle(.borderedProminent)

                    Button("Open System Settings") {
                        model.onOpenAccessibilitySettings?()
                    }
                }
                Spacer()
            }
        case .thumbnails:
            VStack(alignment: .leading, spacing: 20) {
                permissionExplanation(
                    symbol: "rectangle.on.rectangle",
                    title: "Window previews are optional",
                    body: "Thumbnail mode uses Screen Recording to capture small window previews. App Icons and Titles modes never capture window content."
                )
                permissionStatus(
                    granted: model.screenRecordingGranted,
                    grantedText: "Thumbnail previews are enabled",
                    missingText: model.screenRecordingRestartRequired
                        ? "Restart Tab‑List to finish enabling previews"
                        : "You can continue without previews"
                )
                if model.screenRecordingRestartRequired {
                    Text("macOS accepted Screen Recording access, but this running copy of Tab‑List cannot use it yet.")
                        .font(.callout)
                        .foregroundStyle(.secondary)

                    HStack {
                        Button("Quit and Reopen Tab‑List") {
                            model.onQuitAndReopen?()
                        }
                        .buttonStyle(.borderedProminent)

                        continueWithoutPreviewsButton
                    }
                } else {
                    HStack {
                        Button {
                            model.onRequestScreenRecording?()
                        } label: {
                            if model.isRequesting {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Text("Enable Thumbnails")
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(model.isRequesting)

                        continueWithoutPreviewsButton
                    }
                }
                Spacer()
            }
        case .ready:
            VStack(spacing: 24) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 54))
                    .foregroundStyle(.green)
                Text("Tab‑List is ready")
                    .font(.title.bold())
                Text("Press ⌘ Tab to switch windows. Press ⇧ Tab to move backward, press Escape to cancel, or Delete to close the selected window.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: 430)
                Text("Try the shortcut now. This window remains available until you choose Start Using Tab‑List.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
            }
        }
    }

    private var footer: some View {
        HStack {
            Text("Step \(model.step.rawValue + 1) of \(OnboardingViewModel.Step.allCases.count)")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()

            switch model.step {
            case .welcome:
                Button("Continue") { model.advance() }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("onboarding.continue")
            case .accessibility:
                Button("Continue") { model.advance() }
                    .buttonStyle(.borderedProminent)
                    .disabled(!model.accessibilityGranted)
            case .thumbnails:
                EmptyView()
            case .ready:
                Button("Start Using Tab‑List") { model.onFinish?() }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
    }

    private var continueWithoutPreviewsButton: some View {
        Button("Continue without previews") {
            model.onContinueWithoutThumbnails?()
            model.advance()
        }
    }

    private func permissionExplanation(symbol: String, title: LocalizedStringKey, body: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: symbol)
                .font(.system(size: 25))
                .frame(width: 34)
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.headline)
                Text(body).foregroundStyle(.secondary)
            }
        }
    }

    private func permissionStatus(granted: Bool, grantedText: LocalizedStringKey, missingText: LocalizedStringKey) -> some View {
        Label(
            granted ? grantedText : missingText,
            systemImage: granted ? "checkmark.circle.fill" : "exclamationmark.circle"
        )
        .foregroundStyle(granted ? .green : .orange)
    }
}
