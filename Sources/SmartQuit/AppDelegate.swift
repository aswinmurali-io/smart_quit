import AppKit
import Foundation
import SmartQuitCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settings = Settings()
    private let provider = WorkspaceAppsProvider()
    private var engine: QuitEngine!
    private var sweeper: AppSweeper!
    private var statusItem: StatusItemController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        let selfBundleID = Bundle.main.bundleIdentifier ?? "com.smartquit.SmartQuit"

        engine = QuitEngine(
            settings: settings,
            terminator: WorkspaceTerminator(),
            protectedBundleIDs: ["com.apple.finder", selfBundleID]
        )

        sweeper = AppSweeper(
            provider: provider,
            counter: AccessibilityWindowCounter(),
            engine: engine
        )

        statusItem = StatusItemController(
            settings: settings,
            engine: engine,
            provider: provider,
            sweep: { [weak self] in self?.sweeper.sweep() }
        )

        sweeper.onSweepCompleted = { [weak self] in
            self?.statusItem.refreshIcon()
        }

        observeAppTermination()

        // Prompting on first launch is the only way the user learns that the
        // app needs this; without it SmartQuit would silently do nothing.
        if !AccessibilityPermission.requestIfNeeded() {
            Log.ui.notice("Starting without Accessibility permission — window counts unavailable")
        }

        sweeper.start()
        Log.ui.info("SmartQuit started")
    }

    /// Clears state for apps that quit on their own, so a recycled pid never
    /// inherits the previous process's clock.
    private func observeAppTermination() {
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
                    as? NSRunningApplication else { return }
            self?.engine.forget(pid: app.processIdentifier)
            self?.statusItem.refreshIcon()
        }
    }
}
