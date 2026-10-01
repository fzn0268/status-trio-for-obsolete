import CoreWLAN

/// Known bands only; unknown or unavailable channels remain nil.
enum WiFiFrequencyBand: Equatable, Sendable {
    case twoPointFourGHz, fiveGHz, sixGHz

    init?(coreWLANBand: CWChannelBand) {
        switch coreWLANBand {
        case .band2GHz: self = .twoPointFourGHz
        case .band5GHz: self = .fiveGHz
        // `CWChannelBand.band6GHz` is newer than this SDK, so a 6 GHz network
        // reports no band instead of a wrong one.
        default: return nil
        }
    }

    var gigahertz: Double {
        switch self {
        case .twoPointFourGHz: return 2.4
        case .fiveGHz: return 5
        case .sixGHz: return 6
        }
    }
}
