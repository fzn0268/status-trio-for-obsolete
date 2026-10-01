import XCTest

#if swift(<5.9)
// This branch builds with the Swift 5.7 compiler, which predates these test
// APIs. The shims keep the test sources identical for the CI toolchain, which
// compiles the real declarations instead.
extension XCTestCase {
    /// Xcode 14.2's XCTest only has the callback form, and blocking the main
    /// thread with it starves the main actor that fulfils these expectations, so
    /// the wait runs on its own thread like the async API does.
    func fulfillment(
        of expectations: [XCTestExpectation],
        timeout: TimeInterval,
        enforceOrder: Bool = false
    ) async {
        guard !expectations.isEmpty else { return }
        let result: XCTWaiter.Result = await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(
                    returning: XCTWaiter.wait(for: expectations, timeout: timeout, enforceOrder: enforceOrder)
                )
            }
        }
        if result == .timedOut {
            XCTFail("Asynchronous wait failed: exceeded the timeout of \(timeout) seconds.")
        }
    }
}

extension AsyncStream {
    static func makeStream(
        of elementType: Element.Type = Element.self,
        bufferingPolicy limit: Continuation.BufferingPolicy = .unbounded
    ) -> (stream: AsyncStream<Element>, continuation: Continuation) {
        var continuation: Continuation?
        let stream = AsyncStream<Element>(bufferingPolicy: limit) { received in
            continuation = received
        }
        return (stream, continuation!)
    }
}
#endif
