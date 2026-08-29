// SPDX-FileCopyrightText: 2026 Aswin Murali
// SPDX-License-Identifier: GPL-3.0-only

import Foundation

/// Reports which processes are sending audio to an output device right now.
public protocol AudioActivityDetecting: AnyObject {
    /// The process identifiers currently rendering audio output.
    ///
    /// These are processes, not applications. Browsers and Electron apps play
    /// through a helper process, so an emitting pid is frequently a descendant
    /// of the app a person would name. ``AudioAttribution`` resolves them.
    func pidsPlayingAudio() -> Set<pid_t>
}

/// Answers which process launched another.
public protocol ProcessAncestry: AnyObject {
    /// The parent of `pid`, or `nil` when it has none or cannot be read.
    func parent(of pid: pid_t) -> pid_t?
}

/// Maps audio-emitting processes onto the applications they belong to.
public enum AudioAttribution {
    /// How many processes the walk will look at, the emitter included.
    ///
    /// Chrome's audio comes from a renderer two levels below the browser, so
    /// one is not enough. The bound is what stops a corrupt or cyclic parent
    /// chain from spinning the sweep — there is no cycle detection beyond it.
    static let maxDepth = 8

    /// The subset of `appPIDs` that is playing audio, directly or through a
    /// descendant.
    public static func appsPlayingAudio(
        audioPIDs: Set<pid_t>,
        appPIDs: Set<pid_t>,
        ancestry: ProcessAncestry
    ) -> Set<pid_t> {
        var playing: Set<pid_t> = []

        for audioPID in audioPIDs {
            var current: pid_t? = audioPID
            var depth = 0

            while let pid = current, depth < maxDepth {
                if appPIDs.contains(pid) {
                    playing.insert(pid)
                    break
                }
                // launchd is pid 1 and is nobody's application, so the walk
                // stops there rather than climbing the whole system. It is
                // tested for membership first all the same: deciding what to
                // look at is not this function's job.
                guard pid > 1 else { break }

                current = ancestry.parent(of: pid)
                depth += 1
            }
        }

        return playing
    }
}
