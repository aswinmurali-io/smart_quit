// SPDX-FileCopyrightText: 2026 Aswin Murali
// SPDX-License-Identifier: GPL-3.0-only

import XCTest
@testable import SmartQuitCore

final class AppSweeperTests: XCTestCase {
    private var provider: FakeAppsProvider!
    private var counter: FakeWindowCounter!

    override func setUp() {
        super.setUp()
        provider = FakeAppsProvider()
        counter = FakeWindowCounter()
    }

    func testPairsEachAppWithItsWindowCount() {
        provider.apps = [.make(pid: 1, name: "One"), .make(pid: 2, name: "Two")]
        counter.countsByPID = [1: 0, 2: 3]

        let snapshots = AppSweeper.snapshots(for: provider.regularApps(), using: counter)

        XCTAssertEqual(snapshots.map(\.pid), [1, 2])
        XCTAssertEqual(snapshots.map(\.windowCount), [0, 3])
    }

    func testPropagatesAnUnknownWindowCount() {
        provider.apps = [.make(pid: 1)]
        counter.countsByPID = [1: nil]

        let snapshots = AppSweeper.snapshots(for: provider.regularApps(), using: counter)

        XCTAssertNil(snapshots[0].windowCount)
    }

    func testCarriesAppIdentityIntoTheSnapshot() {
        provider.apps = [.make(pid: 7, bundleID: "com.example.Preview", name: "Preview", isFrontmost: true)]

        let snapshots = AppSweeper.snapshots(for: provider.regularApps(), using: counter)

        XCTAssertEqual(snapshots, [
            AppSnapshot(
                pid: 7,
                bundleID: "com.example.Preview",
                name: "Preview",
                isFrontmost: true,
                windowCount: 0
            )
        ])
    }

    /// Without this call a counter that works from a snapshot of the whole
    /// system never takes one, and every app in every sweep is judged against
    /// an empty view of the other Spaces — silently, and only in production.
    func testPreparesTheCounterOnceBeforeCountingAnyApp() {
        provider.apps = [.make(pid: 1), .make(pid: 2), .make(pid: 3)]

        _ = AppSweeper.snapshots(for: provider.regularApps(), using: counter)

        XCTAssertEqual(counter.prepareCount, 1)
        XCTAssertTrue(counter.preparedBeforeFirstQuery)
    }

    func testQueriesEveryApp() {
        provider.apps = [.make(pid: 1), .make(pid: 2), .make(pid: 3)]

        _ = AppSweeper.snapshots(for: provider.regularApps(), using: counter)

        XCTAssertEqual(counter.queried, [1, 2, 3])
    }
}

// MARK: - Frontmost freshness

extension AppSweeperTests {
    /// Counting windows takes time, during which the user can switch apps. The
    /// frontmost app must be re-read afterwards, or SmartQuit can quit the very
    /// app the user just activated.
    func testDoesNotQuitAnAppTheUserActivatedWhileItsWindowsWereCounted() {
        let terminator = SpyTerminator()
        let sweeper = self.sweeper(terminator: terminator)
        provider.apps = [.make(pid: 1)]
        provider.frontmost = nil

        sweepAndWait(sweeper)
        // The user activates the app while the second sweep is counting.
        counter.onQuery = { [weak self] _ in self?.provider.frontmost = 1 }
        sweepAndWait(sweeper)

        XCTAssertEqual(terminator.terminated, [])
    }

    /// Guards the test above: without the activation, the app is quit.
    func testQuitsThatSameAppWhenTheUserDoesNotActivateIt() {
        let terminator = SpyTerminator()
        let sweeper = self.sweeper(terminator: terminator)
        provider.apps = [.make(pid: 1)]
        provider.frontmost = nil

        sweepAndWait(sweeper)
        sweepAndWait(sweeper)

        XCTAssertEqual(terminator.terminated, [1])
    }

    func testReportsEachCompletedSweepExactlyOnce() {
        let sweeper = self.sweeper(terminator: SpyTerminator())
        provider.apps = [.make(pid: 1)]

        var completions = 0
        let done = expectation(description: "swept")
        sweeper.onSweepCompleted = {
            completions += 1
            done.fulfill()
        }
        sweeper.sweep()
        wait(for: [done], timeout: 2)

        XCTAssertEqual(completions, 1)
    }

    // MARK: Helpers

    private func sweeper(
        terminator: SpyTerminator,
        audio: AudioActivityDetecting = FakeAudioActivityDetector(),
        ancestry: ProcessAncestry = FakeProcessAncestry()
    ) -> AppSweeper {
        let settings = FakeSettings()
        // Zero grace: the second sweep is the one that decides.
        settings.globalGracePeriod = 0
        let engine = QuitEngine(
            settings: settings,
            terminator: terminator,
            protectedBundleIDs: []
        )
        return AppSweeper(
            provider: provider,
            counter: counter,
            audio: audio,
            ancestry: ancestry,
            engine: engine
        )
    }

    private func sweepAndWait(_ sweeper: AppSweeper, file: StaticString = #filePath, line: UInt = #line) {
        let done = expectation(description: "sweep")
        sweeper.onSweepCompleted = { done.fulfill() }
        sweeper.sweep()
        wait(for: [done], timeout: 2)
    }
}

// MARK: - Audio

extension AppSweeperTests {
    func testMarksAnAppThatIsPlayingAudio() {
        provider.apps = [.make(pid: 1), .make(pid: 2)]

        let snapshots = AppSweeper.snapshots(
            for: provider.regularApps(),
            using: counter,
            playingAudio: [2]
        )

        XCTAssertEqual(snapshots.map(\.isPlayingAudio), [false, true])
    }

    /// Audio emitted by a helper process pauses the application that owns it.
    func testPausesAnAppWhoseHelperProcessIsPlayingAudio() {
        let terminator = SpyTerminator()
        let audio = FakeAudioActivityDetector()
        let ancestry = FakeProcessAncestry()
        audio.playing = [99]
        ancestry.parents = [99: 1]
        provider.apps = [.make(pid: 1)]

        let sweeper = self.sweeper(terminator: terminator, audio: audio, ancestry: ancestry)
        sweepAndWait(sweeper)
        sweepAndWait(sweeper)

        XCTAssertEqual(terminator.terminated, [])
    }

    /// Guards the test above: with the helper silent, the app is quit.
    func testQuitsThatSameAppWhenNoHelperIsPlaying() {
        let terminator = SpyTerminator()
        provider.apps = [.make(pid: 1)]

        let sweeper = self.sweeper(
            terminator: terminator,
            audio: FakeAudioActivityDetector(),
            ancestry: FakeProcessAncestry()
        )
        sweepAndWait(sweeper)
        sweepAndWait(sweeper)

        XCTAssertEqual(terminator.terminated, [1])
    }
}

// MARK: - Reporting the last sweep

extension AppSweeperTests {
    /// The menu lists apps that have windows, which only the sweep has seen —
    /// the engine drops them as soon as it knows they are not candidates.
    func testKeepsTheSnapshotsFromTheLastSweep() {
        let sweeper = self.sweeper(terminator: SpyTerminator())
        provider.apps = [.make(pid: 1, name: "Safari"), .make(pid: 2, name: "Notes")]
        counter.countsByPID = [1: 3, 2: 0]

        sweepAndWait(sweeper)

        XCTAssertEqual(sweeper.lastSweep?.map(\.name), ["Safari", "Notes"])
        XCTAssertEqual(sweeper.lastSweep?.map(\.windowCount), [3, 0])
    }

    /// Nil, not empty: "no sweep has run" and "nothing has a window" are
    /// different answers and the menu says different things about them.
    func testReportsNothingKnownBeforeTheFirstSweep() {
        XCTAssertNil(sweeper(terminator: SpyTerminator()).lastSweep)
    }
}
