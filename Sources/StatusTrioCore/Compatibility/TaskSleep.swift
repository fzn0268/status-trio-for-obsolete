import Foundation

/// `Task.sleep(for:)` takes a `Duration`, and the whole `Duration` family is
/// macOS 13+: built with `minos 12.0` the binary segfaults on the first call on
/// Monterey, because the symbols are simply not in that release's stdlib. So
/// every interval in this app is a plain `TimeInterval` of seconds, and this is
/// the one place that converts one into a sleep.
///
/// The pre-Tahoe timer API has no tolerance parameter, so the sleeps that ask
/// for one on main simply sleep for the interval and leave coalescing to the OS.
///
/// The constraint matches `Task.sleep(nanoseconds:)` itself, which is only
/// declared for `Task<Never, Never>`; a `where Failure == Never` extension could
/// not reach it.
extension Task where Success == Never, Failure == Never {
    static func sleep(seconds: TimeInterval) async throws {
        try await sleep(nanoseconds: UInt64(max(0, seconds) * 1_000_000_000))
    }
}
