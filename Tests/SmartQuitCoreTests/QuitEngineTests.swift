// SPDX-FileCopyrightText: 2026 Aswin Murali
// SPDX-License-Identifier: GPL-3.0-only

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

// MARK: - Audio pauses the clock

extension QuitEngineTests {
    private var playing: AppSnapshot { .make(pid: 42, windowCount: 0, isPlayingAudio: true) }
    private var silent: AppSnapshot { .make(pid: 42, windowCount: 0) }

    func testDoesNotQuitAnAppThatIsPlayingAudio() {
        engine.apply([playing], now: start)
        engine.apply([playing], now: start.addingTimeInterval(301))
        engine.apply([playing], now: start.addingTimeInterval(3000))

        XCTAssertEqual(terminator.terminated, [])
    }

    /// The clock freezes rather than resetting: time served before the audio
    /// started still counts once it stops.
    func testResumesTheClockWhereItLeftOffWhenAudioStops() {
        engine.apply([silent], now: start)
        // 200s of the 300s grace period served, then audio starts.
        engine.apply([playing], now: start.addingTimeInterval(200))
        engine.apply([playing], now: start.addingTimeInterval(5000))
        // Audio stops with 100s still to serve.
        engine.apply([silent], now: start.addingTimeInterval(5000))
        engine.apply([silent], now: start.addingTimeInterval(5099))

        XCTAssertEqual(terminator.terminated, [])

        engine.apply([silent], now: start.addingTimeInterval(5101))

        XCTAssertEqual(terminator.terminated, [42])
    }

    func testReportsAPausedCountdownWhileAudioPlays() throws {
        engine.apply([silent], now: start)
        engine.apply([playing], now: start.addingTimeInterval(100))

        let countdown = try XCTUnwrap(engine.countdowns(now: start.addingTimeInterval(100)).first)

        XCTAssertTrue(countdown.isPaused)
        XCTAssertEqual(countdown.remaining, 200, accuracy: 0.001)
    }

    /// The menu ticks between sweeps. A paused countdown must not tick.
    func testAPausedCountdownDoesNotTickBetweenSweeps() throws {
        engine.apply([silent], now: start)
        engine.apply([playing], now: start.addingTimeInterval(100))

        let countdown = try XCTUnwrap(engine.countdowns(now: start.addingTimeInterval(160)).first)

        XCTAssertEqual(countdown.remaining, 200, accuracy: 0.001)
    }

    func testAnUnpausedCountdownStillTicksBetweenSweeps() throws {
        engine.apply([silent], now: start)

        let countdown = try XCTUnwrap(engine.countdowns(now: start.addingTimeInterval(60)).first)

        XCTAssertFalse(countdown.isPaused)
        XCTAssertEqual(countdown.remaining, 240, accuracy: 0.001)
    }

    /// An app already playing audio when it goes windowless starts on the
    /// clock, but paused — the menu should say so rather than hide it.
    func testAnAppWindowlessAndAlreadyPlayingStartsPaused() throws {
        engine.apply([playing], now: start)

        let countdown = try XCTUnwrap(engine.countdowns(now: start).first)

        XCTAssertTrue(countdown.isPaused)
        XCTAssertEqual(countdown.remaining, 300, accuracy: 0.001)
    }

    func testAWindowReappearingClearsAPausedClock() {
        engine.apply([playing], now: start)
        engine.apply([.make(pid: 42, windowCount: 1, isPlayingAudio: true)], now: start.addingTimeInterval(10))

        XCTAssertNil(engine.windowlessStart(forPID: 42))
    }
}

// MARK: - The audio pause can be turned off

extension QuitEngineTests {
    func testQuitsAnAppPlayingAudioWhenThePauseIsTurnedOff() {
        settings.pausesWhilePlayingAudio = false

        engine.apply([playing], now: start)
        engine.apply([playing], now: start.addingTimeInterval(301))

        XCTAssertEqual(terminator.terminated, [42])
    }

    /// Turning the pause off resumes a held clock where it stopped rather than
    /// discarding the time already served.
    func testTurningThePauseOffResumesAHeldClock() throws {
        engine.apply([silent], now: start)
        engine.apply([playing], now: start.addingTimeInterval(100))
        engine.apply([playing], now: start.addingTimeInterval(5000))

        settings.pausesWhilePlayingAudio = false
        engine.apply([playing], now: start.addingTimeInterval(5000))

        let countdown = try XCTUnwrap(engine.countdowns(now: start.addingTimeInterval(5000)).first)

        XCTAssertFalse(countdown.isPaused)
        XCTAssertEqual(countdown.remaining, 200, accuracy: 0.001)
    }

    func testTurningThePauseBackOnHoldsTheClockAgain() throws {
        settings.pausesWhilePlayingAudio = false
        engine.apply([playing], now: start)

        settings.pausesWhilePlayingAudio = true
        engine.apply([playing], now: start.addingTimeInterval(100))

        let countdown = try XCTUnwrap(engine.countdowns(now: start.addingTimeInterval(200)).first)

        XCTAssertTrue(countdown.isPaused)
        XCTAssertEqual(countdown.remaining, 200, accuracy: 0.001)
    }
}

// MARK: - Reporting the frontmost app

extension QuitEngineTests {
    func testReportsACountdownAsFrontmost() throws {
        engine.apply([.make(pid: 42, isFrontmost: true, windowCount: 0)], now: start)

        let countdown = try XCTUnwrap(engine.countdowns(now: start).first)

        XCTAssertTrue(countdown.isFrontmost)
    }

    func testReportsACountdownAsNotFrontmost() throws {
        engine.apply([.make(pid: 42, windowCount: 0)], now: start)

        let countdown = try XCTUnwrap(engine.countdowns(now: start).first)

        XCTAssertFalse(countdown.isFrontmost)
    }

    /// Focus moves while an app is on the clock, so the flag has to follow it
    /// rather than being fixed when the clock started.
    func testFollowsFocusWhileAnAppIsOnTheClock() throws {
        engine.apply([.make(pid: 42, windowCount: 0)], now: start)
        engine.apply(
            [.make(pid: 42, isFrontmost: true, windowCount: 0)],
            now: start.addingTimeInterval(15)
        )

        let countdown = try XCTUnwrap(engine.countdowns(now: start.addingTimeInterval(15)).first)

        XCTAssertTrue(countdown.isFrontmost)
    }
}
