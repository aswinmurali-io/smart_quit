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
public final class LingerEngine {
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
        let name: String
        var state: State
    }

    /// How long to wait before checking whether a quit request was honoured.
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

        // Drop state for apps that are no longer running.
        let live = Set(snapshots.map(\.pid))
        tracked = tracked.filter { live.contains($0.key) }

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

        guard let state = tracked[app.pid]?.state else {
            tracked[app.pid] = Tracked(
                bundleID: app.bundleID,
                name: app.name,
                state: .windowless(since: now)
            )
            let grace = settings.gracePeriod(forBundleID: app.bundleID)
            Log.engine.info(
                "\(app.name, privacy: .public) became windowless — quitting in \(grace)s"
            )
            return
        }

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
                    \(Self.verificationDelay)s after quit request — giving up
                    """
                )
                tracked[app.pid]?.state = .surrendered
            } else {
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
        Log.engine.info("\(app.name, privacy: .public) no longer pending — \(reason)")
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
