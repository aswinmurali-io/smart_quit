import Foundation

/// Drives the engine on a fixed interval.
///
/// A single repeating timer sweeps every application, rather than one timer per
/// app. Listing applications and applying decisions happen on the main queue;
/// the Accessibility window counting in between happens off it, because those
/// calls are synchronous and can block on an unresponsive app.
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
        guard timer == nil else { return }
        let timer = Timer.scheduledTimer(withTimeInterval: Self.interval, repeats: true) { [weak self] _ in
            self?.sweep()
        }
        // Keep firing while menus are open.
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        sweep()
    }

    public func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// Performs one sweep: list apps, count their windows, apply the decisions.
    public func sweep() {
        // A sweep that overruns the interval must not stack up behind itself.
        guard !isSweeping else {
            Log.engine.debug("Sweep still in flight — skipping this tick")
            return
        }
        isSweeping = true

        let apps = provider.regularApps()
        countingQueue.async { [weak self] in
            guard let self else { return }
            let snapshots = Self.snapshots(for: apps, using: self.counter)

            DispatchQueue.main.async {
                self.engine.apply(snapshots, now: self.now())
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
