import XCTest
@testable import SmartQuitCore

final class QuitEngineTests: XCTestCase {
    private var settings: FakeSettings!
    private var terminator: SpyTerminator!
    private var engine: QuitEngine!
    private let start = Date(timeIntervalSince1970: 1_000_000)

    override func setUp() {
        super.setUp()
        settings = FakeSettings()
        terminator = SpyTerminator()
        engine = QuitEngine(
            settings: settings,
            terminator: terminator,
            protectedBundleIDs: ["com.apple.finder", "com.smartquit.SmartQuit"]
        )
    }

    // MARK: - Core timing

    func testQuitsAppWindowlessForLongerThanGracePeriod() {
        let app = AppSnapshot.make(pid: 42, windowCount: 0)

        engine.apply([app], now: start)
        engine.apply([app], now: start.addingTimeInterval(301))

        XCTAssertEqual(terminator.terminated, [42])
    }

    func testDoesNotQuitBeforeGracePeriodElapses() {
        let app = AppSnapshot.make(pid: 42, windowCount: 0)

        engine.apply([app], now: start)
        engine.apply([app], now: start.addingTimeInterval(299))

        XCTAssertEqual(terminator.terminated, [])
    }

    func testRestartsClockWhenWindowReappears() {
        let windowless = AppSnapshot.make(pid: 42, windowCount: 0)
        let withWindow = AppSnapshot.make(pid: 42, windowCount: 1)

        engine.apply([windowless], now: start)
        engine.apply([withWindow], now: start.addingTimeInterval(100))
        engine.apply([windowless], now: start.addingTimeInterval(200))
        // 299s since the clock restarted, though 499s since it first started.
        engine.apply([windowless], now: start.addingTimeInterval(499))

        XCTAssertEqual(terminator.terminated, [])
    }

    func testQuitsOnlyOncePerWindowlessSpell() {
        let app = AppSnapshot.make(pid: 42, windowCount: 0)

        engine.apply([app], now: start)
        engine.apply([app], now: start.addingTimeInterval(301))
        engine.apply([app], now: start.addingTimeInterval(316))

        XCTAssertEqual(terminator.terminated, [42])
    }

    // MARK: - Unknown window counts

    func testNeverQuitsAppWhoseWindowCountIsUnknown() {
        let unknown = AppSnapshot.make(pid: 42, windowCount: nil)

        engine.apply([unknown], now: start)
        engine.apply([unknown], now: start.addingTimeInterval(1000))

        XCTAssertEqual(terminator.terminated, [])
    }

    func testUnknownWindowCountDoesNotStartClock() {
        engine.apply([.make(pid: 42, windowCount: nil)], now: start)

        XCTAssertNil(engine.windowlessStart(forPID: 42))
    }

    func testUnknownWindowCountPreservesRunningClock() {
        engine.apply([.make(pid: 42, windowCount: 0)], now: start)
        engine.apply([.make(pid: 42, windowCount: nil)], now: start.addingTimeInterval(100))

        XCTAssertEqual(engine.windowlessStart(forPID: 42), start)
    }

    // MARK: - Ineligible apps

    func testNeverQuitsFrontmostApp() {
        let app = AppSnapshot.make(pid: 42, isFrontmost: true, windowCount: 0)

        engine.apply([app], now: start)
        engine.apply([app], now: start.addingTimeInterval(301))

        XCTAssertEqual(terminator.terminated, [])
    }

    func testFrontmostClockKeepsRunningSoAppQuitsOnceItLosesFocus() {
        let focused = AppSnapshot.make(pid: 42, isFrontmost: true, windowCount: 0)
        let unfocused = AppSnapshot.make(pid: 42, isFrontmost: false, windowCount: 0)

        engine.apply([focused], now: start)
        engine.apply([focused], now: start.addingTimeInterval(301))
        engine.apply([unfocused], now: start.addingTimeInterval(316))

        XCTAssertEqual(terminator.terminated, [42])
    }

    func testNeverQuitsExcludedApp() {
        settings.excludedBundleIDs = ["com.spotify.client"]
        let app = AppSnapshot.make(pid: 42, bundleID: "com.spotify.client", windowCount: 0)

        engine.apply([app], now: start)
        engine.apply([app], now: start.addingTimeInterval(301))

        XCTAssertEqual(terminator.terminated, [])
    }

    func testNeverQuitsProtectedApp() {
        let finder = AppSnapshot.make(pid: 42, bundleID: "com.apple.finder", windowCount: 0)
        let itself = AppSnapshot.make(pid: 43, bundleID: "com.smartquit.SmartQuit", windowCount: 0)

        engine.apply([finder, itself], now: start)
        engine.apply([finder, itself], now: start.addingTimeInterval(301))

        XCTAssertEqual(terminator.terminated, [])
    }

    func testExcludedAppDoesNotAccumulateAClock() {
        settings.excludedBundleIDs = ["com.spotify.client"]

        engine.apply([.make(pid: 42, bundleID: "com.spotify.client", windowCount: 0)], now: start)

        XCTAssertNil(engine.windowlessStart(forPID: 42))
    }

    // MARK: - Global switch

    func testTakesNoActionWhileDisabled() {
        settings.isEnabled = false
        let app = AppSnapshot.make(pid: 42, windowCount: 0)

        engine.apply([app], now: start)
        engine.apply([app], now: start.addingTimeInterval(301))

        XCTAssertEqual(terminator.terminated, [])
    }

    func testDisablingClearsPendingClocks() {
        let app = AppSnapshot.make(pid: 42, windowCount: 0)
        engine.apply([app], now: start)

        settings.isEnabled = false
        engine.apply([app], now: start.addingTimeInterval(15))

        XCTAssertNil(engine.windowlessStart(forPID: 42))
    }

    // MARK: - Per-app grace period

    func testUsesPerAppGracePeriodOverride() {
        settings.perAppGracePeriods = ["com.example.Quick": 60]
        let app = AppSnapshot.make(pid: 42, bundleID: "com.example.Quick", windowCount: 0)

        engine.apply([app], now: start)
        engine.apply([app], now: start.addingTimeInterval(61))

        XCTAssertEqual(terminator.terminated, [42])
    }

    func testPerAppOverrideCanBeLongerThanGlobalGracePeriod() {
        settings.perAppGracePeriods = ["com.example.Slow": 1800]
        let app = AppSnapshot.make(pid: 42, bundleID: "com.example.Slow", windowCount: 0)

        engine.apply([app], now: start)
        engine.apply([app], now: start.addingTimeInterval(301))

        XCTAssertEqual(terminator.terminated, [])
    }

    // MARK: - Process lifecycle

    func testForgettingAppClearsItsClock() {
        engine.apply([.make(pid: 42, windowCount: 0)], now: start)

        engine.forget(pid: 42)

        XCTAssertNil(engine.windowlessStart(forPID: 42))
    }

    func testRelaunchedAppUnderSamePIDStartsAFreshClock() {
        engine.apply([.make(pid: 42, windowCount: 0)], now: start)
        engine.forget(pid: 42)

        engine.apply([.make(pid: 42, windowCount: 0)], now: start.addingTimeInterval(400))
        engine.apply([.make(pid: 42, windowCount: 0)], now: start.addingTimeInterval(500))

        XCTAssertEqual(terminator.terminated, [])
    }

    func testDoesNotLetANewAppInheritTheClockOfARecycledPID() {
        engine.apply([.make(pid: 42, bundleID: "com.example.Old", windowCount: 0)], now: start)

        // The old app quits and a different one is given the same pid before
        // the next sweep, so the terminate notification never cleared it.
        engine.apply(
            [.make(pid: 42, bundleID: "com.example.New", windowCount: 0)],
            now: start.addingTimeInterval(301)
        )

        XCTAssertEqual(terminator.terminated, [])
    }

    func testReportsTheCurrentNameForARecycledPID() {
        engine.apply([.make(pid: 42, bundleID: "com.example.Old", name: "Old", windowCount: 0)], now: start)
        engine.apply([.make(pid: 42, bundleID: "com.example.New", name: "New", windowCount: 0)], now: start)

        XCTAssertEqual(engine.countdowns(now: start).map(\.name), ["New"])
    }

    func testDropsAppsThatDisappearFromTheSweep() {
        engine.apply([.make(pid: 42, windowCount: 0)], now: start)

        engine.apply([], now: start.addingTimeInterval(15))

        XCTAssertNil(engine.windowlessStart(forPID: 42))
    }

    // MARK: - Quit verification

    func testDoesNotRetryWhenTerminateIsRefused() {
        terminator.terminateResult = false
        let app = AppSnapshot.make(pid: 42, windowCount: 0)

        engine.apply([app], now: start)
        engine.apply([app], now: start.addingTimeInterval(301))
        engine.apply([app], now: start.addingTimeInterval(700))

        XCTAssertEqual(terminator.terminated, [42])
    }

    func testDoesNotRetryAnAppThatIsStillRunningAfterTheVerificationDelay() {
        terminator.stillRunningAfterTerminate = [42]
        let app = AppSnapshot.make(pid: 42, windowCount: 0)

        engine.apply([app], now: start)
        engine.apply([app], now: start.addingTimeInterval(301))
        // Past the 10s verification delay, and well past a second grace period.
        engine.apply([app], now: start.addingTimeInterval(320))
        engine.apply([app], now: start.addingTimeInterval(900))

        XCTAssertEqual(terminator.terminated, [42])
    }

    /// A confirmed quit clears the app's state outright, unlike a failed one
    /// which leaves it surrendered and ineligible until a window appears.
    func testAConfirmedQuitLeavesNoStateBehind() {
        let app = AppSnapshot.make(pid: 42, windowCount: 0)

        engine.apply([app], now: start)
        engine.apply([app], now: start.addingTimeInterval(301))
        engine.apply([app], now: start.addingTimeInterval(316))

        engine.apply([app], now: start.addingTimeInterval(331))

        XCTAssertEqual(engine.windowlessStart(forPID: 42), start.addingTimeInterval(331))
    }

    func testAppThatSurvivesAQuitBecomesEligibleAgainOnlyAfterShowingAWindow() {
        terminator.stillRunningAfterTerminate = [42]
        let windowless = AppSnapshot.make(pid: 42, windowCount: 0)
        let withWindow = AppSnapshot.make(pid: 42, windowCount: 1)

        engine.apply([windowless], now: start)
        engine.apply([windowless], now: start.addingTimeInterval(301))
        engine.apply([withWindow], now: start.addingTimeInterval(400))
        engine.apply([windowless], now: start.addingTimeInterval(500))
        engine.apply([windowless], now: start.addingTimeInterval(801))

        XCTAssertEqual(terminator.terminated, [42, 42])
    }

    // MARK: - Countdown reporting

    func testReportsNoCountdownsWhenNothingIsPending() {
        engine.apply([.make(pid: 42, windowCount: 1)], now: start)

        XCTAssertTrue(engine.countdowns(now: start).isEmpty)
    }

    func testReportsRemainingTimeForPendingApp() throws {
        engine.apply([.make(pid: 42, name: "Preview", windowCount: 0)], now: start)

        let countdowns = engine.countdowns(now: start.addingTimeInterval(165))

        XCTAssertEqual(countdowns.count, 1)
        XCTAssertEqual(countdowns.first?.name, "Preview")
        XCTAssertEqual(try XCTUnwrap(countdowns.first).remaining, 135, accuracy: 0.001)
    }

    func testCountdownsAreSortedByUrgency() {
        settings.perAppGracePeriods = ["com.example.Slow": 600]
        engine.apply(
            [
                .make(pid: 1, bundleID: "com.example.Slow", name: "Slow", windowCount: 0),
                .make(pid: 2, bundleID: "com.example.Fast", name: "Fast", windowCount: 0),
            ],
            now: start
        )

        let names = engine.countdowns(now: start).map(\.name)

        XCTAssertEqual(names, ["Fast", "Slow"])
    }

    func testCountdownNeverReportsNegativeRemainingTime() {
        let app = AppSnapshot.make(pid: 42, isFrontmost: true, windowCount: 0)
        engine.apply([app], now: start)
        engine.apply([app], now: start.addingTimeInterval(400))

        XCTAssertEqual(engine.countdowns(now: start.addingTimeInterval(400)).first?.remaining, 0)
    }
}
