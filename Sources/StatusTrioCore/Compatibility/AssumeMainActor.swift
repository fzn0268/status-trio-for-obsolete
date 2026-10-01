/// `MainActor.assumeIsolated` is Swift 5.9+, and the local toolchain is 5.7.
/// Every callback that uses this already runs on the main thread — a
/// `queue: .main` notification handler, a `Timer` on the main run loop, an
/// `NSEvent` local monitor, or a `deinit` — so the isolation is real; this only
/// hands the compiler the proof it cannot infer. It is public because
/// the executable target's top-level code needs the same proof. The bit cast is safe because
/// actor isolation belongs to a closure's type, not to its representation, and
/// `withoutActuallyEscaping` keeps the parameter non-escaping so the call sites
/// keep their existing capture rules.
public func assumingMainActor<T>(_ body: @MainActor () -> T) -> T {
    var result: T?
    withoutActuallyEscaping(body) { escapingBody in
        result = unsafeBitCast(escapingBody, to: (() -> T).self)()
    }
    return result!
}
