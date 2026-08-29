import Foundation

/// Apps excluded on first run.
///
/// These are the ones people habitually leave running with no window open —
/// a music player between tracks, a mail client fetching in the background, a
/// terminal whose window was closed but whose session matters.
public enum DefaultExclusions {
    public static let bundleIDs: Set<String> = [
        "com.spotify.client",        // Spotify
        "com.apple.Music",           // Music
        "com.apple.mail",            // Mail
        "com.apple.MobileSMS",       // Messages
        "com.apple.iCal",            // Calendar
        "com.apple.ActivityMonitor", // Activity Monitor
        "com.apple.Terminal",        // Terminal
        "com.googlecode.iterm2",     // iTerm
    ]
}
