import SwiftUI

extension Animation {
    /// `.snappy(duration:)` is newer than the SDK this branch builds with, so the
    /// list animates with a slightly under-damped spring of the same response:
    /// quick, and it settles without a visible second bounce.
    static func compatibleSnappy(duration: Double) -> Animation {
        .spring(response: duration, dampingFraction: 0.86, blendDuration: 0)
    }
}
