import Combine
import SwiftUI

/// The personal macOS 12 branch has no Sparkle: the dependency cannot be
/// fetched from this machine, so the update UI keeps its call sites and stays
/// permanently disabled instead of linking the framework.
@MainActor
final class UpdaterManager: ObservableObject {
    static let shared = UpdaterManager()

    @Published private(set) var canCheckForUpdates = false
    @Published private(set) var automaticallyChecksForUpdates = false

    var automaticallyChecksForUpdatesBinding: Binding<Bool> {
        Binding(
            get: { self.automaticallyChecksForUpdates },
            set: { _ in }
        )
    }

    private init() {}

    func start(activationPolicy: AppActivationPolicy) {}

    func checkForUpdates() {}
}
