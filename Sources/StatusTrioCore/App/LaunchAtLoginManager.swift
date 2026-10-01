import Combine
import ServiceManagement
import SwiftUI

/// The app's login item registration as reported by the system.
enum LaunchAtLoginStatus: Equatable, Sendable {
    /// The app doesn't launch at login.
    ///
    /// macOS reports an app that has never registered as `notRegistered` on some
    /// versions and `notFound` on others, so both collapse into this case.
    case notRegistered
    /// The app is registered and launches at login.
    case enabled
    /// Registered, but macOS needs the user to approve it in Login Items.
    case requiresApproval
}

/// Abstracts `SMAppService` so the manager can be exercised with a fake.
@MainActor
protocol LaunchAtLoginServicing: AnyObject {
    /// False when the process doesn't run from an app bundle, where macOS cannot
    /// manage a login item at all — for example under `swift run`.
    var isSupported: Bool { get }
    var status: LaunchAtLoginStatus { get }
    func register() throws
    func unregister() throws
    func openLoginItemsSettings()
}

@MainActor
final class SystemLaunchAtLoginService: LaunchAtLoginServicing {
    var isSupported: Bool {
        Self.isSupported(bundledAsApp: Bundle.main.bundleURL.pathExtension == "app")
    }

    /// `SMAppService` is macOS 13+, so below it there is no login-item API for
    /// the app to call and the row has nothing to toggle.
    static func isSupported(bundledAsApp: Bool) -> Bool {
        guard #available(macOS 13.0, *) else { return false }
        return bundledAsApp
    }

    var status: LaunchAtLoginStatus {
        guard #available(macOS 13.0, *) else { return .notRegistered }
        return Self.status(for: SMAppService.mainApp.status)
    }

    /// `SMAppService` answers `notFound` for an app that has never registered a
    /// login item, which is the same situation as `notRegistered` for our UI.
    /// Registering still works from that state, so it must not disable the toggle.
    @available(macOS 13.0, *)
    static func status(for status: SMAppService.Status) -> LaunchAtLoginStatus {
        switch status {
        case .enabled:
            return .enabled
        case .requiresApproval:
            return .requiresApproval
        case .notRegistered, .notFound:
            return .notRegistered
        @unknown default:
            return .notRegistered
        }
    }

    func register() throws {
        guard #available(macOS 13.0, *) else { return }
        try SMAppService.mainApp.register()
    }

    func unregister() throws {
        guard #available(macOS 13.0, *) else { return }
        try SMAppService.mainApp.unregister()
    }

    func openLoginItemsSettings() {
        guard #available(macOS 13.0, *) else { return }
        SMAppService.openSystemSettingsLoginItems()
    }
}

/// Keeps the login item registration in sync with the user's preference and
/// republishes the system state so the settings UI can react to it.
@MainActor
final class LaunchAtLoginManager: ObservableObject {
    static let shared = LaunchAtLoginManager()

    @Published private(set) var status: LaunchAtLoginStatus
    @Published private(set) var didFailLastOperation = false

    private let service: LaunchAtLoginServicing

    init(service: LaunchAtLoginServicing = assumingMainActor { SystemLaunchAtLoginService() }) {
        self.service = service
        self.status = service.status
    }

    /// A registration that still awaits approval counts as on, so the toggle
    /// keeps showing what the user asked for instead of silently flipping back.
    var isEnabled: Bool {
        status == .enabled || status == .requiresApproval
    }

    /// False when macOS cannot manage a login item for this process.
    var isAvailable: Bool {
        service.isSupported
    }

    /// False on a release that has no login-item API at all, which the settings
    /// row explains instead of only greying the toggle out.
    var isSupportedBySystem: Bool {
        if #available(macOS 13.0, *) { return true }
        return false
    }

    var isEnabledBinding: Binding<Bool> {
        Binding(
            get: { self.isEnabled },
            set: { self.setEnabled($0) }
        )
    }

    func setEnabled(_ enabled: Bool) {
        guard isAvailable else { return }
        didFailLastOperation = false

        do {
            if enabled {
                if !isEnabled {
                    try service.register()
                }
            } else if isEnabled {
                try service.unregister()
            }
        } catch {
            didFailLastOperation = true
        }

        refresh()
    }

    func refresh() {
        status = service.status
    }

    func openLoginItemsSettings() {
        service.openLoginItemsSettings()
    }
}
