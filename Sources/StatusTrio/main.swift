import AppKit
import StatusTrioCore

// Top-level code in `main.swift` is the main thread, but Swift 5.7 does not
// infer main-actor isolation for it, so the launch sequence says so itself.
assumingMainActor {
    let application = NSApplication.shared
    let delegate = AppDelegate()
    application.delegate = delegate
    application.run()
}
