import AppKit
import Foundation
import SmartQuitCore

/// The menu bar item and its menu.
///
/// The structure and wording of the menu live in ``MenuModel``; this type only
/// renders that description into AppKit and dispatches the resulting actions.
///
/// The menu is rebuilt when it opens, so it always reflects the apps running at
/// that moment. While it is open, a one-second timer updates only the countdown
/// labels, which keeps them live without collapsing an open submenu.
final class StatusItemController: NSObject, NSMenuDelegate {
    private let statusItem: NSStatusItem
    private let settings: Settings
    private let engine: QuitEngine
    private let provider: RunningAppsProviding
    private let sweep: () -> Void

    /// Countdown rows currently on screen, so they can tick without a rebuild.
    private var countdownItems: [String: NSMenuItem] = [:]
    private var tickTimer: Timer?

    init(
        settings: Settings,
        engine: QuitEngine,
        provider: RunningAppsProviding,
        sweep: @escaping () -> Void
    ) {
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.settings = settings
        self.engine = engine
        self.provider = provider
        self.sweep = sweep
        super.init()

        let menu = NSMenu()
        // Without this AppKit decides enablement itself and the model's
        // isEnabled is silently ignored for top-level items.
        menu.autoenablesItems = false
        menu.delegate = self
        statusItem.menu = menu
        refreshIcon()
    }

    // MARK: - Status icon

    /// The icon carries the app's state at a glance: an empty hourglass when
    /// nothing is waiting, a draining one when apps are on the clock, and a
    /// dimmed icon when SmartQuit is paused.
    func refreshIcon() {
        guard let button = statusItem.button else { return }

        let pending = !engine.countdowns(now: Date()).isEmpty
        let symbol = pending ? "hourglass.bottomhalf.filled" : "hourglass"
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Smart Quit")
        image?.isTemplate = true
        button.image = image
        button.appearsDisabled = !settings.isEnabled

        let state: String
        if !settings.isEnabled {
            state = "paused"
        } else if pending {
            state = "apps on the clock"
        } else {
            state = "nothing waiting"
        }
        button.toolTip = "Smart Quit — \(state)"
    }

    // MARK: - Menu lifecycle

    func menuNeedsUpdate(_ menu: NSMenu) {
        countdownItems.removeAll()
        menu.removeAllItems()
        for node in currentMenuNodes() {
            menu.addItem(render(node))
        }
    }

    func menuWillOpen(_ menu: NSMenu) {
        tickTimer?.invalidate()
        // Menu tracking runs in its own run loop mode, which .common covers.
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            self?.tickCountdowns()
        }
        RunLoop.main.add(timer, forMode: .common)
        tickTimer = timer
    }

    func menuDidClose(_ menu: NSMenu) {
        tickTimer?.invalidate()
        tickTimer = nil
        countdownItems.removeAll()
    }

    private func tickCountdowns() {
        for countdown in engine.countdowns(now: Date()) {
            countdownItems[countdown.bundleID]?.title =
                MenuModel.countdownTitle(for: countdown)
        }
    }

    private func currentMenuNodes() -> [MenuNode] {
        MenuModel.build(
            settings: settings,
            countdowns: engine.countdowns(now: Date()),
            apps: provider.regularApps().sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            },
            isAccessibilityGranted: AccessibilityPermission.isGranted,
            isLaunchAtLoginEnabled: LaunchAtLogin.isEnabled
        )
    }

    // MARK: - Rendering

    private func render(_ node: MenuNode) -> NSMenuItem {
        guard node.kind != .separator else { return .separator() }

        let item = NSMenuItem(title: node.title, action: nil, keyEquivalent: "")
        item.state = node.isChecked ? .on : .off
        item.indentationLevel = node.indent

        switch node.kind {
        case .separator:
            break  // Returned above; the compiler still wants the case.

        case .label:
            item.isEnabled = false

        case .countdown(let bundleID):
            item.isEnabled = false
            countdownItems[bundleID] = item

        case .submenu(let children):
            let submenu = NSMenu()
            submenu.autoenablesItems = false
            for child in children {
                submenu.addItem(render(child))
            }
            item.submenu = submenu

        case .action(.quit):
            item.action = #selector(NSApplication.terminate(_:))
            item.keyEquivalent = "q"

        case .action(let action):
            item.action = #selector(handleMenuAction(_:))
            item.target = self
            item.representedObject = Box(action)
        }

        item.isEnabled = node.isEnabled
        return item
    }

    // MARK: - Actions

    @objc private func handleMenuAction(_ sender: NSMenuItem) {
        guard let action = (sender.representedObject as? Box)?.action else { return }

        switch action {
        case .toggleEnabled:
            settings.isEnabled.toggle()
            Log.ui.info("Enabled set to \(self.settings.isEnabled)")
            sweep()
            refreshIcon()

        case .togglePauseWhilePlayingAudio:
            settings.pausesWhilePlayingAudio.toggle()
            Log.ui.info("Audio pause set to \(self.settings.pausesWhilePlayingAudio)")
            sweep()
            refreshIcon()

        case .setGlobalGracePeriod(let period):
            settings.globalGracePeriod = period
            Log.ui.info("Grace period set to \(Int(period))s")

        case .promptForCustomGracePeriod:
            guard let minutes = CustomGracePeriodPrompt.run(current: settings.globalGracePeriod)
            else { return }
            settings.globalGracePeriod = minutes * 60
            Log.ui.info("Custom grace period set to \(minutes) minutes")

        case .setAppGracePeriod(let bundleID, let period):
            settings.setGracePeriod(period, forBundleID: bundleID)
            Log.ui.info(
                """
                Grace period for \(bundleID, privacy: .public) set to \
                \(period.map { "\(Int($0))s" } ?? "the default", privacy: .public)
                """
            )

        case .toggleExclusion(let bundleID):
            let excluded = !settings.isExcluded(bundleID: bundleID)
            settings.setExcluded(excluded, bundleID: bundleID)
            Log.ui.info("\(bundleID, privacy: .public) excluded: \(excluded)")
            sweep()
            refreshIcon()

        case .openAccessibilitySettings:
            AccessibilityPermission.openSystemSettings()

        case .toggleLaunchAtLogin:
            reportIfLaunchAtLoginFailed(LaunchAtLogin.setEnabled(!LaunchAtLogin.isEnabled))

        case .quit:
            // Rendered with terminate(_:) directly, so it never reaches here.
            NSApp.terminate(nil)
        }
    }

    private func reportIfLaunchAtLoginFailed(_ error: Error?) {
        guard let error else { return }

        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Could not change the login item"
        alert.informativeText = """
            \(error.localizedDescription)

            Launch at login needs Smart Quit to live somewhere stable. Move \
            "Smart Quit.app" to your Applications folder and try again.
            """
        alert.runModal()
    }
}

/// Carries a `MenuAction` on an `NSMenuItem`, which only takes objects.
private final class Box: NSObject {
    let action: MenuAction
    init(_ action: MenuAction) { self.action = action }
}
