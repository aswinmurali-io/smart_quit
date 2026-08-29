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

    private func sweeper(terminator: SpyTerminator) -> AppSweeper {
        let settings = FakeSettings()
        // Zero grace: the second sweep is the one that decides.
        settings.globalGracePeriod = 0
        let engine = QuitEngine(
            settings: settings,
            terminator: terminator,
            protectedBundleIDs: []
        )
        return AppSweeper(provider: provider, counter: counter, engine: engine)
    }

    private func sweepAndWait(_ sweeper: AppSweeper, file: StaticString = #filePath, line: UInt = #line) {
        let done = expectation(description: "sweep")
        sweeper.onSweepCompleted = { done.fulfill() }
        sweeper.sweep()
        wait(for: [done], timeout: 2)
    }
}
