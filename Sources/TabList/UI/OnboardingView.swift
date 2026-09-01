import SwiftUI

@MainActor
final class OnboardingViewModel: ObservableObject {
    enum Step: Int, CaseIterable {
        case welcome
        case accessibility
        case ready
    }

    @Published var step: Step = .welcome
    @Published var accessibilityGranted = false

    var onRequestAccessibility: (() -> Void)?
    var onOpenAccessibilitySettings: (() -> Void)?
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
        .frame(width: 620, height: 440)
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
                explanation(
                    symbol: "keyboard",
                    title: "A faster window switcher",
                    body: "Hold Command and press Tab to move through every open macOS window as a list. Release Command to activate the selected window."
                )
                explanation(
                    symbol: "hand.raised",
                    title: "Private by design",
                    body: "Window information stays on this Mac. Tab‑List has no analytics, never captures window content, and never uploads window titles."
                )
                Spacer()
            }
        case .accessibility:
            VStack(alignment: .leading, spacing: 20) {
                explanation(
                    symbol: "accessibility",
                    title: "Allow Accessibility",
                    body: "This is the only permission Tab‑List needs. It lets Tab‑List read the list of open windows, observe the shortcut, and activate or close the window you choose."
                )
                Label(
                    model.accessibilityGranted
                        ? "Accessibility is enabled"
                        : "Accessibility is required",
                    systemImage: model.accessibilityGranted
                        ? "checkmark.circle.fill"
                        : "exclamationmark.circle"
                )
                .foregroundStyle(model.accessibilityGranted ? .green : .orange)

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
                Text("Try the shortcut now. This window stays available until you choose Start Using Tab‑List.")
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
            case .ready:
                Button("Start Using Tab‑List") { model.onFinish?() }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
    }

    private func explanation(
        symbol: String,
        title: LocalizedStringKey,
        body: LocalizedStringKey
    ) -> some View {
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
}
