import XCTest
@testable import LingererCore

final class SettingsTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "dev.aswinmurali.Lingerer.tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    // MARK: - Defaults

    func testIsEnabledByDefault() {
        XCTAssertTrue(Settings(defaults: defaults).isEnabled)
    }

    func testDefaultGracePeriodIsFiveMinutes() {
        XCTAssertEqual(Settings(defaults: defaults).globalGracePeriod, 300)
    }

    func testSeedsDefaultExclusionsOnFirstRun() {
        let settings = Settings(defaults: defaults)

        XCTAssertEqual(settings.excludedBundleIDs, DefaultExclusions.bundleIDs)
    }

    func testDoesNotReseedExclusionsTheUserHasRemoved() {
        let first = Settings(defaults: defaults)
        first.setExcluded(false, bundleID: "com.spotify.client")

        let second = Settings(defaults: defaults)

        XCTAssertFalse(second.isExcluded(bundleID: "com.spotify.client"))
    }

    // MARK: - Persistence

    func testPersistsEnabledState() {
        Settings(defaults: defaults).isEnabled = false

        XCTAssertFalse(Settings(defaults: defaults).isEnabled)
    }

    func testPersistsGlobalGracePeriod() {
        Settings(defaults: defaults).globalGracePeriod = 600

        XCTAssertEqual(Settings(defaults: defaults).globalGracePeriod, 600)
    }

    func testPersistsExclusions() {
        Settings(defaults: defaults).setExcluded(true, bundleID: "com.example.App")

        XCTAssertTrue(Settings(defaults: defaults).isExcluded(bundleID: "com.example.App"))
    }

    // MARK: - Per-app grace periods

    func testFallsBackToGlobalGracePeriodWithoutAnOverride() {
        let settings = Settings(defaults: defaults)
        settings.globalGracePeriod = 120

        XCTAssertEqual(settings.gracePeriod(forBundleID: "com.example.App"), 120)
    }

    func testPersistsPerAppGracePeriodOverride() {
        Settings(defaults: defaults).setGracePeriod(60, forBundleID: "com.example.App")

        XCTAssertEqual(Settings(defaults: defaults).gracePeriod(forBundleID: "com.example.App"), 60)
    }

    func testClearingAnOverrideRestoresTheGlobalGracePeriod() {
        let settings = Settings(defaults: defaults)
        settings.globalGracePeriod = 300
        settings.setGracePeriod(60, forBundleID: "com.example.App")

        settings.setGracePeriod(nil, forBundleID: "com.example.App")

        XCTAssertEqual(settings.gracePeriod(forBundleID: "com.example.App"), 300)
    }

    func testReportsWhichAppsHaveAnOverride() {
        let settings = Settings(defaults: defaults)
        settings.setGracePeriod(60, forBundleID: "com.example.App")

        XCTAssertEqual(settings.gracePeriodOverride(forBundleID: "com.example.App"), 60)
        XCTAssertNil(settings.gracePeriodOverride(forBundleID: "com.example.Other"))
    }

    // MARK: - Guards

    func testRejectsANonPositiveGracePeriod() {
        let settings = Settings(defaults: defaults)

        settings.globalGracePeriod = 0

        XCTAssertEqual(settings.globalGracePeriod, 300)
    }
}
