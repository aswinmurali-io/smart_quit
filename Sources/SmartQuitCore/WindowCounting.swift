// SPDX-FileCopyrightText: 2026 Aswin Murali
// SPDX-License-Identifier: GPL-3.0-only

import Foundation

/// Counts the standard windows an application has open.
///
/// This is the seam for the window-detection strategy: swapping the
/// Accessibility implementation for another approach means writing one
/// conforming type.
public protocol WindowCounting: AnyObject {
    /// The number of standard windows belonging to `pid`.
    ///
    /// Returns `nil` when the count could not be determined — the app did not
    /// respond, or Accessibility permission is missing. Callers must treat that
    /// as "unknown", never as zero.
    func standardWindowCount(pid: pid_t) -> Int?
}
