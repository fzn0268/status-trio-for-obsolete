import SwiftUI

/// `Image(systemName:variableValue:)` is macOS 13+, and the Wi-Fi glyph is the
/// one place the app leans on it: the variable value is how the arcs fill with
/// signal strength. Below macOS 13 the same glyph draws at its default value
/// instead of failing to resolve.
struct VariableValueSymbol: View {
    let name: String
    var variableValue: Double = 1.0

    var body: some View {
        if #available(macOS 13.0, *) {
            Image(
                systemName: CompatibleSymbol.resolve(name),
                variableValue: variableValue
            )
        } else {
            Image(systemName: CompatibleSymbol.resolve(name))
        }
    }
}
