import AppKit

/// Apple adds and renames glyphs with most system releases, and a name the
/// running system does not ship draws as nothing at all — not a placeholder,
/// not an error, just an empty frame.
///
/// Resolution is a catalog lookup rather than an `#available` check because the
/// catalog belongs to the release the user is on, not to the SDK the app was
/// built against. The lists are ordered most faithful first, and the last entry
/// is a name old enough to ship everywhere, the same rule
/// `AudioOutputDeviceIcon.symbolCandidates` follows.
enum CompatibleSymbol {
    /// Plainer or older spellings for the glyphs this app draws by name rather
    /// than through a candidate list.
    private static let aliases: [String: [String]] = [
        "powerplug.portrait.fill": ["powerplug.fill", "powerplug"],
        "apple.logo": ["applelogo"],
        "flask.fill": ["testtube.2"],
    ]

    static func candidates(for name: String) -> [String] {
        [name] + (aliases[name] ?? [])
    }

    static func isAvailable(_ name: String) -> Bool {
        NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil
    }

    /// The first of `name`'s spellings the running system can actually draw.
    static func resolve(_ name: String) -> String {
        candidates(for: name).first(where: isAvailable) ?? name
    }

    /// The variable value — the fill level of a `wifi` or `battery` glyph — is a
    /// macOS 13 addition. Below it the symbol draws at its default value, which
    /// keeps the glyph present and costs only the graded fill.
    static func image(_ name: String, variableValue: Double = 1.0) -> NSImage? {
        let resolved = resolve(name)
        if #available(macOS 13.0, *) {
            return NSImage(
                systemSymbolName: resolved,
                variableValue: variableValue,
                accessibilityDescription: nil
            )
        }
        return NSImage(systemSymbolName: resolved, accessibilityDescription: nil)
    }
}
