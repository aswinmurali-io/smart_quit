import Foundation

/// Drives the engine on a fixed interval.
///
/// A single repeating timer sweeps every application, rather than one timer per
/// app. Listing applications and applying decisions happen on the main queue;
/// the Accessibility window counting in between happens off it, because those
/// calls are synchronous and can block on an unresponsive app.
///
/// - Important: ``start()``, ``sweep()`` and the engine they drive are main
///   queue only. Nothing here is synchronised, and the background hop is
///   deliberately given no access to this object's state — it works from values
///   captured before it starts. The entry points assert the queue rather than
///   trusting callers.
public final class AppSweeper {
    /// How often the system is swept.
    public static let interval: TimeInterval = 15

    private let provider: RunningAppsProviding
    private let counter: WindowCounting
    private let engine: LingerEngine
    private let now: () -> Date
    private let countingQueue = DispatchQueue(
        label: "dev.aswinmurali.Lingerer.window-counting",
        qos: .utility
    )

    private var timer: Timer?
    private var isSweeping = false

    /// Called after each sweep so the UI can refresh.
    public var onSweepCompleted: (() -> Void)?

    public init(
        provider: RunningAppsProviding,
        counter: WindowCounting,
        engine: LingerEngine,
        now: @escaping () -> Date = Date.init
    ) {
        self.provider = provider
        self.counter = counter
        self.engine = engine
        self.now = now
    }

    // MARK: - Running

    public func start() {
        dispatchPrecondition(condition: .onQueue(.main))
        guard timer == nil else { return }

        // Scheduled in .common so the sweep keeps running while a menu is open;
        // scheduledTimer would install it in .default only.
        let timer = Timer(timeInterval: Self.interval, repeats: true) { [weak self] _ in
            self?.sweep()
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        sweep()
    }

    /// Performs one sweep: list apps, count their windows, apply the decisions.
    public func sweep() {
        dispatchPrecondition(condition: .onQueue(.main))

        // A sweep that overruns the interval must not stack up behind itself.
        guard !isSweeping else {
            Log.engine.debug("Sweep still in flight — skipping this tick")
            return
        }
        isSweeping = true

        let apps = provider.regularApps()
        // Captured up front so the background work touches none of our state.
        let counter = self.counter

        countingQueue.async { [weak self] in
            let snapshots = Self.snapshots(for: apps, using: counter)

            DispatchQueue.main.async {
                guard let self else { return }
                // Re-read the frontmost app rather than trusting the value
                // captured before counting began. Counting takes time, and
                // quitting the app the user just switched to would be the worst
                // thing this app could do.
                let frontmost = self.provider.frontmostPID()
                let fresh = snapshots.map { $0.withFrontmost($0.pid == frontmost) }

                self.engine.apply(fresh, now: self.now())
                self.isSweeping = false
                self.onSweepCompleted?()
            }
        }
    }

    /// Pairs each app with its current window count.
    static func snapshots(for apps: [RunningApp], using counter: WindowCounting) -> [AppSnapshot] {
        apps.map { AppSnapshot($0, windowCount: counter.standardWindowCount(pid: $0.pid)) }
    }
}
