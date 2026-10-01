import SwiftUI

/// The keys the option grid moves its selection with. The grid still names them;
/// on this branch they drive nothing, because `KeyEquivalent` and `onKeyPress`
/// are macOS 14 types and methods that the SDK here does not have at all.
enum SelectionKey {
    case leftArrow, rightArrow, upArrow, downArrow, space, returnKey
}

extension View {
    /// Below macOS 14 there is no key-press modifier, so the cards stay reachable
    /// with Tab and still activate with Space through the button itself, but the
    /// group cannot move its selection with the arrow keys.
    @ViewBuilder
    func onSelectionKey(_ key: SelectionKey, action: @escaping () -> Void) -> some View {
        self
    }

    /// Without `focusEffectDisabled()` the system draws its own focus ring over
    /// the card's selection ring.
    @ViewBuilder
    func withoutFocusEffect() -> some View {
        self
    }
}
