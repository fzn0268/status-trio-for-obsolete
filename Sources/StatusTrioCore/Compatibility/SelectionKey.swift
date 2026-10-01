import SwiftUI

/// The keys the option grid moves its selection with. Named here because
/// `KeyEquivalent` is itself a macOS 14 type, so a compatibility shim cannot
/// take it as a parameter.
enum SelectionKey {
    case leftArrow, rightArrow, upArrow, downArrow, space, returnKey

    @available(macOS 14.0, *)
    var keyEquivalent: KeyEquivalent {
        switch self {
        case .leftArrow: .leftArrow
        case .rightArrow: .rightArrow
        case .upArrow: .upArrow
        case .downArrow: .downArrow
        case .space: .space
        case .returnKey: .return
        }
    }
}

extension View {
    /// `onKeyPress` is macOS 14+. Below it the cards stay reachable with Tab and
    /// still activate with Space through the button itself, but the group has no
    /// way to move the selection with the arrow keys.
    @ViewBuilder
    func onSelectionKey(_ key: SelectionKey, action: @escaping () -> Void) -> some View {
        if #available(macOS 14.0, *) {
            onKeyPress(key.keyEquivalent) {
                action()
                return .handled
            }
        } else {
            self
        }
    }

    /// `focusEffectDisabled()` is macOS 14+. Without it the system draws its own
    /// focus ring over the card's selection ring.
    @ViewBuilder
    func withoutFocusEffect() -> some View {
        if #available(macOS 14.0, *) {
            focusEffectDisabled()
        } else {
            self
        }
    }
}
