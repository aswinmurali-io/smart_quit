import Foundation

/// Something the user can do from the menu.
public enum MenuAction: Equatable {
    case toggleEnabled
    case togglePauseWhilePlayingAudio
    case setGlobalGracePeriod(TimeInterval)
    case promptForCustomGracePeriod
    case setAppGracePeriod(bundleID: String, period: TimeInterval?)
    case toggleExclusion(bundleID: String)
    case openAccessibilitySettings
    case toggleLaunchAtLogin
    case quit
}

/// One row of the menu.
public struct MenuNode: Equatable {
    public enum Kind: Equatable {
        case separator
        /// A label the user cannot act on: a section heading or a status line.
        case label
        /// A live countdown row, identified so its label can tick in place.
        case countdown(bundleID: String)
        case action(MenuAction)
        case submenu([MenuNode])
    }

    public let title: String
    public let kind: Kind
    public let isChecked: Bool
    public let isEnabled: Bool
    public let indent: Int

    public init(
        title: String,
        kind: Kind,
        isChecked: Bool = false,
        isEnabled: Bool = true,
        indent: Int = 0
    ) {
        self.title = title
        self.kind = kind
        self.isChecked = isChecked
        self.isEnabled = isEnabled
        self.indent = indent
    }

    static let separator = MenuNode(title: "", kind: .separator, isEnabled: false)

    static func label(_ title: String, indent: Int = 0) -> MenuNode {
        MenuNode(title: title, kind: .label, isEnabled: false, indent: indent)
    }
}

/// Builds the menu as data.
///
/// Keeping the menu's structure and wording out of AppKit means both can be
/// asserted in tests, and the status item is left with nothing to do but render.
public enum MenuModel {
    public static func build(
        settings: Settings,
        countdowns: [Countdown],
        apps: [RunningApp],
        isAccessibilityGranted: Bool,
        isLaunchAtLoginEnabled: Bool
    ) -> [MenuNode] {
        var nodes: [MenuNode] = []

        // Without Accessibility permission nothing else in this menu has any
        // effect, so the problem and its fix come before everything else.
        if !isAccessibilityGranted {
            nodes.append(.label("Needs Accessibility permission to see windows"))
            nodes.append(
                MenuNode(
                    title: "Open Accessibility Settings…",
                    kind: .action(.openAccessibilitySettings)
                )
            )
            nodes.append(.separator)
        }

        nodes.append(
            MenuNode(
                title: "Quit idle apps",
                kind: .action(.toggleEnabled),
                isChecked: settings.isEnabled
            )
        )
        // Beside the main switch rather than buried in a submenu: both decide
        // whether an app gets quit at all, where everything below only decides
        // when.
        nodes.append(
            MenuNode(
                title: "Pause apps playing audio",
                kind: .action(.togglePauseWhilePlayingAudio),
                isChecked: settings.pausesWhilePlayingAudio
            )
        )
        nodes.append(.separator)

        nodes += clockSection(
            countdowns: countdowns,
            isEnabled: settings.isEnabled,
            isAccessibilityGranted: isAccessibilityGranted
        )
        nodes.append(.separator)
        nodes.append(gracePeriodMenu(settings: settings, apps: apps))
        nodes.append(exclusionsMenu(settings: settings, apps: apps))
        nodes.append(.separator)

        if isAccessibilityGranted {
            nodes.append(
                MenuNode(
                    title: "Open Accessibility Settings…",
                    kind: .action(.openAccessibilitySettings)
                )
            )
        }
        nodes.append(
            MenuNode(
                title: "Launch at login",
                kind: .action(.toggleLaunchAtLogin),
                isChecked: isLaunchAtLoginEnabled
            )
        )
        nodes.append(.separator)
        nodes.append(MenuNode(title: "Quit SmartQuit", kind: .action(.quit)))

        return nodes
    }

    // MARK: - Sections

    private static func clockSection(
        countdowns: [Countdown],
        isEnabled: Bool,
        isAccessibilityGranted: Bool
    ) -> [MenuNode] {
        // The interval comes from the sweeper rather than being written out
        // here: an unchanged list is the normal case, and a user who cannot
        // tell refresh rate from staleness has no way to know that.
        var nodes: [MenuNode] = [
            .label("On the clock — checks every \(CountdownFormatter.string(for: AppSweeper.interval))")
        ]

        guard !countdowns.isEmpty else {
            // "Nothing waiting" would be a lie when we cannot see windows at all.
            let reason: String
            if !isAccessibilityGranted {
                reason = "Can't see windows without permission"
            } else if !isEnabled {
                reason = "Paused"
            } else {
                reason = "Nothing waiting to quit"
            }
            nodes.append(.label(reason, indent: 1))
            return nodes
        }

        nodes += countdowns.map {
            MenuNode(
                title: countdownTitle(for: $0),
                kind: .countdown(bundleID: $0.bundleID),
                isEnabled: false,
                indent: 1
            )
        }
        return nodes
    }

    /// The label for one countdown row.
    ///
    /// Public because the status item ticks these rows in place while the menu
    /// is open, and has to write the same text the menu was built with.
    public static func countdownTitle(for countdown: Countdown) -> String {
        // The frozen number is not worth showing: what the user needs to know
        // is that the app is safe for as long as it keeps playing.
        guard !countdown.isPaused else { return "\(countdown.name) — paused (playing audio)" }
        return "\(countdown.name) — \(CountdownFormatter.string(for: countdown.remaining))"
    }

    private static func gracePeriodMenu(settings: Settings, apps: [RunningApp]) -> MenuNode {
        var children: [MenuNode] = Settings.gracePeriodPresets.map { preset in
            MenuNode(
                title: CountdownFormatter.gracePeriodLabel(for: preset),
                kind: .action(.setGlobalGracePeriod(preset)),
                isChecked: settings.globalGracePeriod == preset
            )
        }

        // A value that is not one of the presets can only have come from here,
        // so this is where it is shown as selected.
        children.append(
            MenuNode(
                title: "Custom…",
                kind: .action(.promptForCustomGracePeriod),
                isChecked: !Settings.gracePeriodPresets.contains(settings.globalGracePeriod)
            )
        )
        children.append(.separator)
        children.append(perAppGracePeriodMenu(settings: settings, apps: apps))

        return MenuNode(
            title: "Grace period — \(CountdownFormatter.gracePeriodLabel(for: settings.globalGracePeriod))",
            kind: .submenu(children)
        )
    }

    private static func perAppGracePeriodMenu(settings: Settings, apps: [RunningApp]) -> MenuNode {
        guard !apps.isEmpty else {
            return MenuNode(title: "Per-app grace periods", kind: .submenu([.label("No apps running")]))
        }

        let children = apps.map { app -> MenuNode in
            let override = settings.gracePeriodOverride(forBundleID: app.bundleID)

            var options: [MenuNode] = [
                MenuNode(
                    title: "Use default",
                    kind: .action(.setAppGracePeriod(bundleID: app.bundleID, period: nil)),
                    isChecked: override == nil
                ),
                .separator,
            ]
            options += Settings.gracePeriodPresets.map { preset in
                MenuNode(
                    title: CountdownFormatter.gracePeriodLabel(for: preset),
                    kind: .action(.setAppGracePeriod(bundleID: app.bundleID, period: preset)),
                    isChecked: override == preset
                )
            }

            let title = override.map {
                "\(app.name) — \(CountdownFormatter.gracePeriodLabel(for: $0))"
            } ?? app.name
            return MenuNode(title: title, kind: .submenu(options))
        }

        return MenuNode(title: "Per-app grace periods", kind: .submenu(children))
    }

    private static func exclusionsMenu(settings: Settings, apps: [RunningApp]) -> MenuNode {
        guard !apps.isEmpty else {
            return MenuNode(title: "Excluded apps", kind: .submenu([.label("No apps running")]))
        }

        let children = apps.map { app in
            MenuNode(
                title: app.name,
                kind: .action(.toggleExclusion(bundleID: app.bundleID)),
                isChecked: settings.isExcluded(bundleID: app.bundleID)
            )
        }
        return MenuNode(title: "Excluded apps", kind: .submenu(children))
    }
}
