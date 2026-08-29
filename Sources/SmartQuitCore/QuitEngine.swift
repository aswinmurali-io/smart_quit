import Foundation

/// Decides which applications to quit, based on how long they have been
/// windowless.
///
/// The engine holds no timers and performs no I/O of its own: a caller sweeps
/// the system, hands over ``AppSnapshot`` values and the current time, and the
/// engine updates its state and issues termination requests. Everything below
/// is therefore directly testable without a window server.
///
/// State is keyed by pid rather than bundle identifier so that an app which
/// quits and relaunches gets a fresh clock instead of inheriting a stale one.
///
/// - Important: Main queue only. Nothing here is synchronised.
public final class QuitEngine {
    /// Where an app sits in its journey from "windowless" to "quit".
    private enum State {
        /// Has had no windows since this date.
        case windowless(since: Date)
        /// We asked it to quit at this date and are waiting to see if it went.
        case quitRequested(at: Date)
        /// We asked, it stayed. We do not ask again until it shows a window.
        case surrendered
    }

    /// An app being tracked, with enough identity to render it in the menu.
    private struct Tracked {
        let bundleID: String
        var name: String
        var state: State
    }

    /// How long to wait before checking whether a quit request was honoured.
    ///
    /// Checked during a sweep rather than on its own timer, so the effective
    /// delay is the first sweep at or after this point — up to one sweep
    /// interval later. That is fine: the check only decides whether to stop
    /// asking, and asking later is harmless.
    static let verificationDelay: TimeInterval = 10

    private let settings: SettingsProviding
    private let terminator: AppTerminating
    private let protectedBundleIDs: Set<String>

    private var tracked: [pid_t: Tracked] = [:]

    public init(
        settings: SettingsProviding,
        terminator: AppTerminating,
        protectedBundleIDs: Set<String>
    ) {
        self.settings = settings
        self.terminator = terminator
        self.protectedBundleIDs = protectedBundleIDs
    }

    // MARK: - Sweeping

    /// Processes one sweep of the system.
    public func apply(_ snapshots: [AppSnapshot], now: Date) {
        guard settings.isEnabled else {
            if !tracked.isEmpty {
                Log.engine.debug("Disabled — clearing \(self.tracked.count) pending timer(s)")
                tracked.removeAll()
            }
            return
        }

        // Drop state for apps that are no longer running. An app we had asked
        // to quit and that has now gone is the confirmation that it worked —
        // this is where a successful quit is observed, because the app is
        // pruned here before it can reach the verification branch below.
        let live = Set(snapshots.map(\.pid))
        for (pid, entry) in tracked where !live.contains(pid) {
            if case .quitRequested = entry.state {
                Log.engine.info("\(entry.name, privacy: .public) quit")
            }
            tracked[pid] = nil
        }

        for app in snapshots {
            advance(app, now: now)
        }
    }

    private func advance(_ app: AppSnapshot, now: Date) {
        // An unknown count means the Accessibility query failed or timed out.
        // Hold whatever state we have rather than treating it as windowless.
        guard let windowCount = app.windowCount else { return }

        guard windowCount == 0 else {
            stopTracking(app, reason: "has \(windowCount) window(s)")
            return
        }

        guard isEligible(app) else {
            stopTracking(app, reason: "not eligible")
            return
        }

        // Pids are recycled. If a different app now holds this one, the state
        // belongs to the process that died, not to this one.
        if let entry = tracked[app.pid], entry.bundleID != app.bundleID {
            Log.engine.debug("pid \(app.pid) is now \(app.bundleID, privacy: .public) — resetting")
            tracked[app.pid] = nil
        }

        guard let state = tracked[app.pid]?.state else {
            tracked[app.pid] = Tracked(
                bundleID: app.bundleID,
                name: app.name,
                state: .windowless(since: now)
            )
            let grace = settings.gracePeriod(forBundleID: app.bundleID)
            Log.engine.info(
                "\(app.name, privacy: .public) became windowless — quitting in \(Int(grace))s"
            )
            return
        }

        tracked[app.pid]?.name = app.name

        switch state {
        case .windowless(let since):
            let grace = settings.gracePeriod(forBundleID: app.bundleID)
            guard now.timeIntervalSince(since) >= grace else { return }
            requestQuit(of: app, now: now)

        case .quitRequested(let at):
            guard now.timeIntervalSince(at) >= Self.verificationDelay else { return }
            if terminator.isRunning(pid: app.pid) {
                Log.engine.error(
                    """
                    \(app.name, privacy: .public) still running \
                    \(Int(Self.verificationDelay))s after quit request — giving up
                    """
                )
                tracked[app.pid]?.state = .surrendered
            } else {
                Log.engine.info("\(app.name, privacy: .public) quit")
                tracked[app.pid] = nil
            }

        case .surrendered:
            // Waiting for the app to show a window before reconsidering it.
            return
        }
    }

    private func requestQuit(of app: AppSnapshot, now: Date) {
        // Never quit what the user is looking at. The clock keeps running, so
        // the app goes as soon as it loses focus.
        guard !app.isFrontmost else {
            Log.engine.debug("\(app.name, privacy: .public) is due but frontmost — holding")
            return
        }

        Log.engine.info("Quitting \(app.name, privacy: .public)")
        if terminator.terminate(pid: app.pid) {
            tracked[app.pid]?.state = .quitRequested(at: now)
        } else {
            Log.engine.error("\(app.name, privacy: .public) refused the quit request — giving up")
            tracked[app.pid]?.state = .surrendered
        }
    }

    private func stopTracking(_ app: AppSnapshot, reason: String) {
        guard tracked[app.pid] != nil else { return }
        Log.engine.info("\(app.name, privacy: .public) no longer pending — \(reason, privacy: .public)")
        tracked[app.pid] = nil
    }

    private func isEligible(_ app: AppSnapshot) -> Bool {
        !protectedBundleIDs.contains(app.bundleID) && !settings.isExcluded(bundleID: app.bundleID)
    }

    // MARK: - Lifecycle

    /// Drops all state for an app, for use when it terminates on its own.
    public func forget(pid: pid_t) {
        tracked[pid] = nil
    }

    // MARK: - Reporting

    /// Apps currently on the clock, most urgent first.
    public func countdowns(now: Date) -> [Countdown] {
        tracked.compactMap { pid, entry -> Countdown? in
            guard case .windowless(let since) = entry.state else { return nil }

            let grace = settings.gracePeriod(forBundleID: entry.bundleID)
            let remaining = max(0, grace - now.timeIntervalSince(since))
            return Countdown(
                pid: pid,
                bundleID: entry.bundleID,
                name: entry.name,
                remaining: remaining
            )
        }
        .sorted { ($0.remaining, $0.name) < ($1.remaining, $1.name) }
    }

    /// When an app's windowless clock started, or `nil` if it is not on the clock.
    func windowlessStart(forPID pid: pid_t) -> Date? {
        guard case .windowless(let since) = tracked[pid]?.state else { return nil }
        return since
    }
}
