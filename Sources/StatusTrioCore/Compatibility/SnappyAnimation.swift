import SwiftUI

extension Animation {
    /// `.snappy(duration:)` is newer than macOS 12, so it is asked for only on the
    /// release where its availability is certain. A slightly under-damped spring of
    /// the same response is the closest curve the older releases offer: quick, and it
    /// settles without a visible second bounce.
    static func compatibleSnappy(duration: Double) -> Animation {
        if #available(macOS 15.0, *) {
            return .snappy(duration: duration)
        }
        return .spring(response: duration, dampingFraction: 0.86, blendDuration: 0)
    }
}
