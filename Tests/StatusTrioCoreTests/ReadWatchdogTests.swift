import XCTest
@testable import StatusTrioCore

@MainActor
final class ReadWatchdogTests: XCTestCase {
    func testTimeoutStartsAtTheBaseAndDoublesUpToTheCap() async {
        let sleeper = ManualEventSleeper()
        let watchdog = ReadWatchdog(
            baseTimeout: 1,
            maxTimeout: 8,
            sleep: { duration in await sleeper.sleep(duration) }
        )

        for index in 0..<5 {
            let fired = expectation(description: "watchdog \(index) fired")
            watchdog.arm { fired.fulfill() }
            let armed = await sleeper.waitForCallCount(index + 1, timeout: 5)
            XCTAssertTrue(armed, "The watchdog must arm a timer for read \(index)")
            sleeper.releaseAll()
            await fulfillment(of: [fired], timeout: 5)
        }

        XCTAssertEqual(
            sleeper.durations,
            [1, 2, 4, 8, 8],
            "Consecutive timeouts must back off and then stay at the cap"
        )
    }

    func testRecordSuccessResetsTheBackoff() async {
        let sleeper = ManualEventSleeper()
        let watchdog = ReadWatchdog(
            baseTimeout: 1,
            maxTimeout: 8,
            sleep: { duration in await sleeper.sleep(duration) }
        )

        for index in 0..<3 {
            let fired = expectation(description: "watchdog \(index) fired")
            watchdog.arm { fired.fulfill() }
            let armed = await sleeper.waitForCallCount(index + 1, timeout: 5)
            XCTAssertTrue(armed, "The watchdog must arm a timer for read \(index)")
            sleeper.releaseAll()
            await fulfillment(of: [fired], timeout: 5)
        }

        watchdog.recordSuccess()

        let afterReset = expectation(description: "watchdog after reset fired")
        watchdog.arm { afterReset.fulfill() }
        let armedAfterReset = await sleeper.waitForCallCount(4, timeout: 5)
        XCTAssertTrue(armedAfterReset, "The watchdog must arm a timer after a successful read")
        sleeper.releaseAll()
        await fulfillment(of: [afterReset], timeout: 5)

        XCTAssertEqual(
            sleeper.durations,
            [1, 2, 4, 1],
            "A returned read means the system is responsive again"
        )
    }

    func testCancelledWatchdogDoesNotReportATimeout() async {
        let sleeper = ManualEventSleeper()
        let watchdog = ReadWatchdog(
            baseTimeout: 1,
            maxTimeout: 8,
            sleep: { duration in await sleeper.sleep(duration) }
        )
        let notFired = expectation(description: "a cancelled watchdog never fires")
        notFired.isInverted = true

        watchdog.arm { notFired.fulfill() }
        let armed = await sleeper.waitForCallCount(1, timeout: 5)
        XCTAssertTrue(armed, "The watchdog must arm a timer, otherwise this test proves nothing")
        watchdog.cancel()
        sleeper.releaseAll()

        await fulfillment(of: [notFired], timeout: 0.2)
    }
}
