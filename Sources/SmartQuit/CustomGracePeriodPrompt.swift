import AppKit
import Foundation

/// Asks for a grace period in minutes.
enum CustomGracePeriodPrompt {
    /// Accepted range, in minutes. A grace period of a fraction of a second
    /// would quit apps the moment their last window closed.
    static let range: ClosedRange<Double> = 1...1440

    /// Returns the chosen number of minutes, or `nil` if the user cancelled or
    /// typed something that is not a positive number.
    static func run(current: TimeInterval) -> Double? {
        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.messageText = "Grace period"
        alert.informativeText = """
            Quit an app after this many minutes without a window. \
            Between \(Int(range.lowerBound)) and \(Int(range.upperBound)).
            """
        alert.addButton(withTitle: "Set")
        alert.addButton(withTitle: "Cancel")

        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
        field.placeholderString = "Minutes"
        field.stringValue = trimmedMinutes(from: current)
        alert.accessoryView = field
        alert.window.initialFirstResponder = field

        guard alert.runModal() == .alertFirstButtonReturn else { return nil }

        guard let minutes = Double(field.stringValue.trimmingCharacters(in: .whitespaces)),
              range.contains(minutes) else { return nil }
        return minutes
    }

    /// Renders the current value without a trailing ".0".
    private static func trimmedMinutes(from period: TimeInterval) -> String {
        let minutes = period / 60
        return minutes == minutes.rounded()
            ? String(Int(minutes))
            : String(format: "%.1f", minutes)
    }
}
