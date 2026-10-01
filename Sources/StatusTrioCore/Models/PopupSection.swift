import Foundation

enum PopupSection: String, CaseIterable, Identifiable, Sendable {
    case battery
    case network
    case vpn
    case bluetooth
    case volume
    case audioInput

    var id: Self { self }

    var titleKey: LocalizationKey {
        switch self {
        case .battery: return .settingsPopupOrderBattery
        case .network: return .settingsPopupOrderNetwork
        case .vpn: return .vpnTitle
        case .bluetooth: return .bluetoothTitle
        case .volume: return .settingsPopupOrderVolume
        case .audioInput: return .settingsPopupOrderAudioInput
        }
    }

    var systemImage: String {
        switch self {
        case .battery: return "battery.100percent"
        case .network: return "wifi"
        case .vpn: return "lock.shield"
        case .bluetooth: return "antenna.radiowaves.left.and.right"
        case .volume: return "speaker.wave.2"
        case .audioInput: return "mic"
        }
    }
}
