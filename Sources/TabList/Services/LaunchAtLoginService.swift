import Foundation
import ServiceManagement

public enum LaunchAtLoginState: String, Codable, Sendable {
    case enabled
    case disabled
    case requiresApproval
    case notFound
}

public enum LaunchAtLoginError: Error, Sendable {
    case requiresUserApproval
    case registrationFailed(String)
}

/// `SMAppService` remains the source of truth; no duplicate preference is kept.
@MainActor
public final class LaunchAtLoginService {
    public init() {}

    public var state: LaunchAtLoginState {
        switch SMAppService.mainApp.status {
        case .enabled:
            return .enabled
        case .requiresApproval:
            return .requiresApproval
        case .notFound:
            return .notFound
        case .notRegistered:
            return .disabled
        @unknown default:
            return .disabled
        }
    }

    public func setEnabled(_ enabled: Bool) throws {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            if SMAppService.mainApp.status == .requiresApproval {
                throw LaunchAtLoginError.requiresUserApproval
            }
            throw LaunchAtLoginError.registrationFailed(
                String(describing: error)
            )
        }
    }

    public func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
