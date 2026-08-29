import XCTest
@testable import LingererCore

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
