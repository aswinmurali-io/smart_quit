import AppKit
import Foundation

/// Asks for a grace period in minutes.
enum CustomGracePeriodPrompt {
    /// Accepted range, in minutes. A grace period of a fraction of a second
    /// would quit apps the moment their last window closed.
    static let range: ClosedRange<Double> = 1...1440

    /// Returns the chosen number of minutes, or `nil` if the user cancelled.
    ///
    /// An entry that is not a number in range is not silently dropped: it says
    /// so and asks again. Closing the dialog on a rejected value is
    /// indistinguishable from having pressed Cancel, which leaves someone who
    /// typed 5000 believing they set a grace period they did not.
    static func run(current: TimeInterval) -> Double? {
        var value = trimmedMinutes(from: current)

        while true {
            guard let typed = ask(startingFrom: value) else { return nil }

            if let minutes = Double(typed.trimmingCharacters(in: .whitespaces)),
               range.contains(minutes) {
                return minutes
            }

            reportRejected(typed)
            value = typed
        }
    }

    /// One turn of the dialog. Returns what was typed, or `nil` for Cancel.
    private static func ask(startingFrom value: String) -> String? {
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
        field.stringValue = value
        alert.accessoryView = field
        alert.window.initialFirstResponder = field

        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        return field.stringValue
    }

    /// Says what was wrong, so the retry is not a guess.
    private static func reportRejected(_ typed: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "That is not a grace period"
        alert.informativeText = """
            "\(typed)" is not a number of minutes between \
            \(Int(range.lowerBound)) and \(Int(range.upperBound)).
            """
        alert.runModal()
    }

    /// Renders the current value without a trailing ".0".
    private static func trimmedMinutes(from period: TimeInterval) -> String {
        let minutes = period / 60
        return minutes == minutes.rounded()
            ? String(Int(minutes))
            : String(format: "%.1f", minutes)
    }
}
