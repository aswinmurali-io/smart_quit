import Foundation

/// Renders durations for the menu.
public enum CountdownFormatter {
    /// A ticking countdown, as "2m 15s".
    ///
    /// Seconds are zero-padded so the label keeps a steady width while it
    /// counts down, and the value rounds up so a countdown with time left never
    /// reads as zero.
    public static func string(for remaining: TimeInterval) -> String {
        let total = Int(ceil(max(0, remaining)))

        if total >= 3600 {
            return "\(total / 3600)h \(total % 3600 / 60)m"
        }
        if total >= 60 {
            return String(format: "%dm %02ds", total / 60, total % 60)
        }
        return "\(total)s"
    }

    /// A grace period setting, as "5 minutes".
    public static func gracePeriodLabel(for period: TimeInterval) -> String {
        let total = Int(period.rounded())
        guard total >= 60, total % 60 == 0 else { return string(for: period) }

        if total % 3600 == 0 {
            let hours = total / 3600
            return hours == 1 ? "1 hour" : "\(hours) hours"
        }

        let minutes = total / 60
        return minutes == 1 ? "1 minute" : "\(minutes) minutes"
    }
}
