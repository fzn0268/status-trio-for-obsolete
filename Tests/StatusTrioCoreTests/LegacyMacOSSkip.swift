import XCTest

extension XCTestCase {
    /// Marks the assertions that measure what a newer system draws: an SVG loaded
    /// as an `NSImage`, the graded fill of the `wifi` symbol, the metrics of a
    /// symbol name this release does not ship, or an AppKit host view per drawn
    /// button. This branch runs on macOS 12, where those behaviours do not exist,
    /// so the check skips instead of failing.
    func skipUnlessMacOS13OrNewer(_ what: String) throws {
        guard #available(macOS 13.0, *) else {
            throw XCTSkip("\(what) requires macOS 13")
        }
    }

    /// The hit-area rows are only realized at their full width by the newer
    /// SDK's SwiftUI, which vends a full-width key-view proxy inside a window.
    func skipUnlessFullWidthKeyViewProxy() throws {
        guard #available(macOS 26.0, *) else {
            throw XCTSkip("the full-width key-view proxy needs the current design language")
        }
    }
}
