import Foundation

@testable import StatusTrioCore

/// Records the ticks a player asked for, so the gate and the coalescing can be
/// asserted without making a sound. Shared because both the swift-testing and
/// the XCTest suites drive it.
@MainActor
final class FakeVolumeFeedbackPlayer: VolumeFeedbackPlaying {
    private(set) var playCount = 0

    func playVolumeChangeFeedback() { playCount += 1 }
}
