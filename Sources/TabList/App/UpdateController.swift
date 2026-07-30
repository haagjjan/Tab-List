import AppKit
import Foundation

#if canImport(Sparkle)
@preconcurrency import Sparkle
#endif

/// Keeps Sparkle optional in command-line type checks while using the real
/// framework in the generated Xcode project.
@MainActor
final class UpdateController {
#if canImport(Sparkle)
    private let controller: SPUStandardUpdaterController?
#endif

    init(automaticallyChecksForUpdates: Bool) {
#if canImport(Sparkle)
        let key = Bundle.main.object(
            forInfoDictionaryKey: "SUPublicEDKey"
        ) as? String
        guard key?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        else {
            controller = nil
            return
        }

        let controller = SPUStandardUpdaterController(
            startingUpdater: false,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        controller.updater.automaticallyChecksForUpdates =
            automaticallyChecksForUpdates
        controller.startUpdater()
        self.controller = controller
#endif
    }

    var isConfigured: Bool {
#if canImport(Sparkle)
        controller != nil
#else
        false
#endif
    }

    func setAutomaticallyChecksForUpdates(_ enabled: Bool) {
#if canImport(Sparkle)
        controller?.updater.automaticallyChecksForUpdates = enabled
#endif
    }

    @discardableResult
    func checkForUpdates() -> Bool {
#if canImport(Sparkle)
        guard let controller else { return false }
        controller.checkForUpdates(nil)
        return true
#else
        return false
#endif
    }
}
