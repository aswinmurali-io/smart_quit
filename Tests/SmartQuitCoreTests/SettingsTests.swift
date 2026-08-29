import XCTest
@testable import SmartQuitCore

final class SettingsTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "com.smartquit.SmartQuit.tests.\(UUID().uuidString)"
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

    /// A stored value can be non-positive even though the setter refuses one —
    /// `defaults write` reaches around it. A grace period of zero or less makes
    /// every windowless app due on its first sweep, so it must not be honoured.
    func testIgnoresAStoredGracePeriodThatIsNotPositive() {
        defaults.set(-1.0, forKey: "globalGracePeriod")

        XCTAssertEqual(Settings(defaults: defaults).globalGracePeriod, 300)
    }

    /// Losing the whole exclusion list to one bad entry would make every
    /// protected app quittable, so a malformed entry must cost only itself.
    func testKeepsValidExclusionsWhenAStoredEntryIsNotAString() {
        defaults.set(true, forKey: "hasSeededExclusions")
        defaults.set(["com.example.Good", 42], forKey: "excludedBundleIDs")

        XCTAssertEqual(Settings(defaults: defaults).excludedBundleIDs, ["com.example.Good"])
    }

    func testKeepsValidOverridesWhenAStoredEntryIsNotANumber() {
        defaults.set(
            ["com.example.Good": 60.0, "com.example.Bad": "not a number"],
            forKey: "gracePeriodOverrides"
        )
        let settings = Settings(defaults: defaults)

        XCTAssertEqual(settings.gracePeriod(forBundleID: "com.example.Good"), 60)
        XCTAssertEqual(settings.gracePeriod(forBundleID: "com.example.Bad"), 300)
    }
}

// MARK: - The audio pause

extension SettingsTests {
    func testPausesWhilePlayingAudioByDefault() {
        XCTAssertTrue(Settings(defaults: defaults).pausesWhilePlayingAudio)
    }

    func testPersistsTheAudioPauseSetting() {
        Settings(defaults: defaults).pausesWhilePlayingAudio = false

        XCTAssertFalse(Settings(defaults: defaults).pausesWhilePlayingAudio)
    }
}
