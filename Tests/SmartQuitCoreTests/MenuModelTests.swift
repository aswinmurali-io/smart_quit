// SPDX-FileCopyrightText: 2026 Aswin Murali
// SPDX-License-Identifier: GPL-3.0-only

import XCTest
@testable import SmartQuitCore

final class MenuModelTests: XCTestCase {
    private var suiteName: String!
    private var settings: Settings!

    override func setUp() {
        super.setUp()
        suiteName = "com.smartquit.SmartQuit.tests.\(UUID().uuidString)"
        settings = Settings(defaults: UserDefaults(suiteName: suiteName)!)
    }

    override func tearDown() {
        UserDefaults().removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    private func build(
        countdowns: [Countdown] = [],
        apps: [RunningApp] = [],
        accessibilityGranted: Bool = true,
        launchAtLogin: Bool = false,
        version: String? = "0.1.0",
        foregroundApp: String? = nil,
        openApps: [AppSnapshot]? = []
    ) -> [MenuNode] {
        MenuModel.build(
            settings: settings,
            countdowns: countdowns,
            apps: apps,
            isAccessibilityGranted: accessibilityGranted,
            isLaunchAtLoginEnabled: launchAtLogin,
            version: version,
            foregroundAppName: foregroundApp,
            openApps: openApps
        )
    }

    // MARK: - Top level

    func testLeadsWithTheToggleThatNamesWhatItControls() {
        let first = build().first

        XCTAssertEqual(first?.title, "Quit idle apps")
        XCTAssertEqual(first?.kind, .action(.toggleEnabled))
        XCTAssertTrue(first?.isChecked == true)
    }

    func testEndsWithQuit() {
        XCTAssertEqual(build().last?.kind, .action(.quit))
    }

    func testShowsEveryTopLevelSection() {
        let titles = build().filter { $0.kind != .separator }.map(\.title)

        XCTAssertEqual(titles, [
            "Quit idle apps",
            "Pause apps playing audio",
            "On the clock — checks every 3s",
            "Nothing waiting to quit",
            "With windows — 0",
            "No apps showing windows",
            "Grace period — 5 minutes",
            "Excluded apps",
            "Open Accessibility Settings…",
            "Launch at login",
            "Version 0.1.0",
            "Check for Updates…",
            "Quit Smart Quit",
        ])
    }

    // MARK: - Countdown section

    func testListsAppsOnTheClockWithTheirRemainingTime() {
        let nodes = build(countdowns: [
            Countdown(pid: 1, bundleID: "com.example.Preview", name: "Preview", remaining: 135),
        ])

        XCTAssertTrue(nodes.contains { $0.title == "Preview — 2m 15s" })
    }

    func testIndentsCountdownsUnderTheirHeader() {
        let nodes = build(countdowns: [
            Countdown(pid: 1, bundleID: "com.example.Preview", name: "Preview", remaining: 135),
        ])
        let countdown = nodes.first { $0.title.hasPrefix("Preview") }

        XCTAssertEqual(countdown?.indent, 1)
        XCTAssertFalse(countdown?.isEnabled == true)
    }

    func testSaysNothingIsWaitingWhenTheClockIsEmpty() {
        XCTAssertTrue(build().contains { $0.title == "Nothing waiting to quit" })
    }

    func testSaysPausedRatherThanEmptyWhenDisabled() {
        settings.isEnabled = false

        XCTAssertTrue(build().contains { $0.title == "Paused" })
    }

    // MARK: - Grace period

    func testOffersEveryGracePeriodPreset() {
        let submenu = self.submenu(titled: "Grace period — 5 minutes", in: build())
        let titles = submenu.filter { $0.kind != .separator }.map(\.title)

        XCTAssertEqual(titles, [
            "1 minute", "2 minutes", "5 minutes", "10 minutes", "30 minutes",
            "Custom…", "Per-app grace periods",
        ])
    }

    func testChecksTheSelectedGracePeriod() {
        settings.globalGracePeriod = 600
        let submenu = self.submenu(titled: "Grace period — 10 minutes", in: build())

        XCTAssertTrue(submenu.first { $0.title == "10 minutes" }?.isChecked == true)
        XCTAssertFalse(submenu.first { $0.title == "5 minutes" }?.isChecked == true)
    }

    func testChecksCustomWhenTheValueIsNotAPreset() {
        settings.globalGracePeriod = 420
        let submenu = self.submenu(titled: "Grace period — 7 minutes", in: build())

        XCTAssertTrue(submenu.first { $0.title == "Custom…" }?.isChecked == true)
    }

    // MARK: - Per-app grace periods

    func testOffersAPerAppOverrideForEachRunningApp() {
        let nodes = build(apps: [.make(bundleID: "com.example.Safari", name: "Safari")])
        let perApp = submenu(titled: "Per-app grace periods", in: submenu(titled: "Grace period — 5 minutes", in: nodes))

        XCTAssertEqual(perApp.map(\.title), ["Safari"])
    }

    func testShowsAnActiveOverrideInTheAppTitle() {
        settings.setGracePeriod(600, forBundleID: "com.example.Safari")
        let nodes = build(apps: [.make(bundleID: "com.example.Safari", name: "Safari")])
        let perApp = submenu(titled: "Per-app grace periods", in: submenu(titled: "Grace period — 5 minutes", in: nodes))

        XCTAssertEqual(perApp.map(\.title), ["Safari — 10 minutes"])
    }

    func testAnAppWithoutAnOverrideUsesTheDefault() {
        let nodes = build(apps: [.make(bundleID: "com.example.Safari", name: "Safari")])
        let perApp = submenu(titled: "Per-app grace periods", in: submenu(titled: "Grace period — 5 minutes", in: nodes))
        let safari = submenu(titled: "Safari", in: perApp)

        XCTAssertTrue(safari.first { $0.title == "Use default" }?.isChecked == true)
    }

    // MARK: - Exclusions

    func testListsRunningAppsForExclusion() {
        let nodes = build(apps: [
            .make(bundleID: "com.example.Safari", name: "Safari"),
            .make(bundleID: "com.example.Notes", name: "Notes"),
        ])

        XCTAssertEqual(submenu(titled: "Excluded apps", in: nodes).map(\.title), ["Safari", "Notes"])
    }

    func testChecksExcludedApps() {
        settings.setExcluded(true, bundleID: "com.example.Safari")
        let nodes = build(apps: [.make(bundleID: "com.example.Safari", name: "Safari")])

        XCTAssertTrue(submenu(titled: "Excluded apps", in: nodes).first?.isChecked == true)
    }

    func testSaysSoWhenNoAppsAreRunning() {
        XCTAssertEqual(submenu(titled: "Excluded apps", in: build()).map(\.title), ["No apps running"])
    }

    // MARK: - Permission

    func testWarnsWhenAccessibilityPermissionIsMissing() {
        let nodes = build(accessibilityGranted: false)

        XCTAssertTrue(nodes.contains { $0.title == "Needs Accessibility permission to see windows" })
    }

    func testLeadsWithTheWarningWhenPermissionIsMissing() {
        let nodes = build(accessibilityGranted: false)

        // Without the permission nothing else in the menu does anything, so the
        // warning and its fix come before the settings.
        XCTAssertEqual(nodes.first?.title, "Needs Accessibility permission to see windows")
        XCTAssertEqual(nodes.dropFirst().first?.kind, .action(.openAccessibilitySettings))
    }

    func testSaysWindowsAreInvisibleRatherThanClaimingNothingIsWaiting() {
        let nodes = build(accessibilityGranted: false)

        XCTAssertTrue(nodes.contains { $0.title == "Can't see windows without permission" })
        XCTAssertFalse(nodes.contains { $0.title == "Nothing waiting to quit" })
    }

    func testDoesNotWarnOncePermissionIsGranted() {
        let nodes = build(accessibilityGranted: true)

        XCTAssertFalse(nodes.contains { $0.title.contains("Needs Accessibility") })
    }

    func testAlwaysOffersTheSettingsShortcut() {
        for granted in [true, false] {
            let nodes = build(accessibilityGranted: granted)
            XCTAssertTrue(nodes.contains { $0.kind == .action(.openAccessibilitySettings) })
        }
    }

    // MARK: - Helpers

    private func submenu(titled title: String, in nodes: [MenuNode]) -> [MenuNode] {
        guard let node = nodes.first(where: { $0.title == title }),
              case .submenu(let children) = node.kind else {
            XCTFail("No submenu titled \(title)")
            return []
        }
        return children
    }
}

// MARK: - Paused countdowns

extension MenuModelTests {
    func testSaysAPausedCountdownIsWaitingOnAudio() {
        let nodes = build(countdowns: [
            Countdown(
                pid: 1,
                bundleID: "com.spotify.client",
                name: "Spotify",
                remaining: 135,
                isPaused: true
            ),
        ])

        XCTAssertTrue(nodes.contains { $0.title == "Spotify — paused (playing audio)" })
    }

    /// The status item ticks countdown rows in place, so it needs the same
    /// title the menu was built with.
    func testRendersTheSameTitleTheMenuUses() {
        let countdown = Countdown(
            pid: 1,
            bundleID: "com.example.Preview",
            name: "Preview",
            remaining: 135
        )
        let nodes = build(countdowns: [countdown])

        XCTAssertTrue(nodes.contains { $0.title == MenuModel.countdownTitle(for: countdown) })
    }
}

// MARK: - The audio pause toggle

extension MenuModelTests {
    func testOffersTheAudioPauseAsAToggleBesideTheMainSwitch() {
        let nodes = build()
        let index = nodes.firstIndex { $0.kind == .action(.togglePauseWhilePlayingAudio) }

        XCTAssertEqual(index, 1)
        XCTAssertEqual(nodes[1].title, "Pause apps playing audio")
    }

    func testChecksTheAudioPauseWhenItIsOn() {
        settings.pausesWhilePlayingAudio = true

        let node = build().first { $0.kind == .action(.togglePauseWhilePlayingAudio) }

        XCTAssertEqual(node?.isChecked, true)
    }

    func testUnchecksTheAudioPauseWhenItIsOff() {
        settings.pausesWhilePlayingAudio = false

        let node = build().first { $0.kind == .action(.togglePauseWhilePlayingAudio) }

        XCTAssertEqual(node?.isChecked, false)
    }
}

// MARK: - The clock header

extension MenuModelTests {
    func testTheClockHeaderStatesHowOftenItChecks() {
        XCTAssertTrue(build().contains { $0.title == "On the clock — checks every 3s" })
    }

    /// Derived from the sweeper's interval rather than written out, so the two
    /// cannot drift apart.
    func testTheClockHeaderFollowsTheSweepInterval() {
        let header = build().first { $0.title.hasPrefix("On the clock") }

        XCTAssertEqual(
            header?.title,
            "On the clock — checks every \(CountdownFormatter.string(for: AppSweeper.interval))"
        )
    }
}

// MARK: - Version and updates

extension MenuModelTests {
    func testShowsTheVersionItWasGiven() {
        let nodes = build(version: "0.1.0")

        XCTAssertTrue(nodes.contains { $0.title == "Version 0.1.0" })
    }

    /// The row is a label, not something to click.
    func testTheVersionIsNotActionable() {
        let node = build(version: "0.1.0").first { $0.title == "Version 0.1.0" }

        XCTAssertEqual(node?.kind, .label)
        XCTAssertEqual(node?.isEnabled, false)
    }

    /// Reading the version can fail — under xctest `Bundle.main` is the test
    /// runner. Saying nothing beats showing "Version unknown".
    func testOmitsTheVersionRowWhenTheVersionIsNotKnown() {
        XCTAssertFalse(build(version: nil).contains { $0.title.hasPrefix("Version") })
    }

    func testOffersToCheckForUpdates() {
        let node = build().first { $0.kind == .action(.checkForUpdates) }

        XCTAssertEqual(node?.title, "Check for Updates…")
        XCTAssertEqual(node?.isEnabled, true)
    }

    /// Still offered when the version is unknown: that is when someone most
    /// wants to go and look.
    func testOffersUpdatesEvenWithoutAVersion() {
        XCTAssertTrue(build(version: nil).contains { $0.kind == .action(.checkForUpdates) })
    }

    func testPutsTheVersionDirectlyAboveTheUpdateCheck() throws {
        let nodes = build(version: "0.1.0")
        let version = try XCTUnwrap(nodes.firstIndex { $0.title == "Version 0.1.0" })
        let updates = try XCTUnwrap(nodes.firstIndex { $0.kind == .action(.checkForUpdates) })

        XCTAssertEqual(updates, version + 1)
    }

    func testReleasesURLPointsAtTheProjectsReleases() {
        XCTAssertEqual(
            AppInfo.releasesURL?.absoluteString,
            "https://github.com/aswinmurali-io/smart_quit/releases"
        )
    }
}

// MARK: - The foreground app

extension MenuModelTests {
    private func countdown(
        name: String = "Preview",
        remaining: TimeInterval = 135,
        isPaused: Bool = false,
        isFrontmost: Bool = false
    ) -> Countdown {
        Countdown(
            pid: 1,
            bundleID: "com.example.\(name)",
            name: name,
            remaining: remaining,
            isPaused: isPaused,
            isFrontmost: isFrontmost
        )
    }

    func testMarksACountdownThatIsInFront() {
        let title = MenuModel.countdownTitle(for: countdown(name: "Safari", isFrontmost: true))

        XCTAssertEqual(title, "Safari — 2m 15s (foreground)")
    }

    /// A paused app keeps its existing wording; being in front adds to it
    /// rather than replacing it.
    func testMarksACountdownThatIsBothPausedAndInFront() {
        let title = MenuModel.countdownTitle(
            for: countdown(name: "Spotify", isPaused: true, isFrontmost: true)
        )

        XCTAssertEqual(title, "Spotify — paused (playing audio, foreground)")
    }

    func testLeavesAnOrdinaryCountdownUnmarked() {
        XCTAssertEqual(MenuModel.countdownTitle(for: countdown()), "Preview — 2m 15s")
    }

    func testNamesTheAppInFront() {
        XCTAssertTrue(build(foregroundApp: "Safari").contains { $0.title == "In front — Safari" })
    }

    func testTheForegroundRowIsALabel() {
        let node = build(foregroundApp: "Safari").first { $0.title.hasPrefix("In front") }

        XCTAssertEqual(node?.kind, .label)
        XCTAssertEqual(node?.isEnabled, false)
    }

    func testOmitsTheForegroundRowWhenNothingIsKnown() {
        XCTAssertFalse(build(foregroundApp: nil).contains { $0.title.hasPrefix("In front") })
    }

    /// Context before the list it explains.
    func testPutsTheForegroundRowAboveTheClockHeader() throws {
        let nodes = build(foregroundApp: "Safari")
        let front = try XCTUnwrap(nodes.firstIndex { $0.title.hasPrefix("In front") })
        let clock = try XCTUnwrap(nodes.firstIndex { $0.title.hasPrefix("On the clock") })

        XCTAssertEqual(clock, front + 1)
    }
}

// MARK: - Apps with windows

extension MenuModelTests {
    /// The rows indented under the "With windows" heading.
    private func windowed(_ nodes: [MenuNode]) -> [MenuNode] {
        guard let start = nodes.firstIndex(where: { $0.title.hasPrefix("With windows") })
        else { return [] }
        return Array(nodes[(start + 1)...].prefix { $0.indent == 1 })
    }

    func testCountsTheAppsShowingWindows() {
        let nodes = build(openApps: [
            .make(pid: 1, name: "Safari", windowCount: 2),
            .make(pid: 2, name: "Xcode", windowCount: 1),
            .make(pid: 3, name: "Notes", windowCount: 0),
        ])

        XCTAssertTrue(nodes.contains { $0.title == "With windows — 2" })
    }

    func testListsEachAppWithItsWindowCount() {
        let children = windowed(build(openApps: [
            .make(pid: 1, name: "Safari", windowCount: 2),
            .make(pid: 2, name: "Xcode", windowCount: 1),
        ]))

        XCTAssertEqual(children.map(\.title), ["Safari — 2 windows", "Xcode — 1 window"])
    }

    /// A windowless app belongs on the clock, not in this list.
    func testLeavesOutAppsWithNoWindows() {
        let children = windowed(build(openApps: [.make(pid: 1, name: "Notes", windowCount: 0)]))

        XCTAssertEqual(children.map(\.title), ["No apps showing windows"])
    }

    /// An unreadable count is not evidence of a window, the same way it is not
    /// evidence of none.
    func testLeavesOutAppsWhoseCountIsUnknown() {
        let children = windowed(build(openApps: [.make(pid: 1, name: "Xcode", windowCount: nil)]))

        XCTAssertEqual(children.map(\.title), ["No apps showing windows"])
    }

    func testSortsAppsWithWindowsByName() {
        let children = windowed(build(openApps: [
            .make(pid: 1, name: "Xcode", windowCount: 1),
            .make(pid: 2, name: "Finder", windowCount: 1),
            .make(pid: 3, name: "safari", windowCount: 1),
        ]))

        XCTAssertEqual(children.map(\.title).map { String($0.prefix(6)) }, ["Finder", "safari", "Xcode "])
    }

    func testTheWindowRowsAreNotActionable() {
        let children = windowed(build(openApps: [.make(pid: 1, name: "Safari", windowCount: 1)]))

        XCTAssertEqual(children.first?.kind, .label)
        XCTAssertEqual(children.first?.isEnabled, false)
    }
}

// MARK: - Fixes locked in

extension MenuModelTests {
    /// Before any sweep has finished, nothing is known — which is not the same
    /// as nothing having a window.
    func testSaysTheWindowListIsNotCheckedYet() {
        let nodes = build(openApps: nil)

        XCTAssertTrue(nodes.contains { $0.title == "With windows" })
        XCTAssertTrue(nodes.contains { $0.title == "Not checked yet" })
    }

    func testDoesNotClaimZeroWindowsBeforeASweep() {
        XCTAssertFalse(build(openApps: nil).contains { $0.title.contains("With windows — ") })
    }

    /// Two instances of one app are two clocks. Keyed by bundle identifier they
    /// would collide and only one row could ever tick.
    func testGivesEachInstanceOfAnAppItsOwnCountdownRow() {
        let nodes = build(countdowns: [
            Countdown(pid: 1, bundleID: "com.example.App", name: "App", remaining: 60),
            Countdown(pid: 2, bundleID: "com.example.App", name: "App", remaining: 120),
        ])
        let kinds = nodes.compactMap { node -> MenuNode.Kind? in
            if case .countdown = node.kind { return node.kind }
            return nil
        }

        XCTAssertEqual(kinds, [.countdown(pid: 1), .countdown(pid: 2)])
    }
}
