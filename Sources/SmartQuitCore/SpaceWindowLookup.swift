// SPDX-FileCopyrightText: 2026 Aswin Murali
// SPDX-License-Identifier: GPL-3.0-only

import CoreGraphics
import Foundation

/// The window server's view of windows that are not on a Space the user is
/// currently looking at.
///
/// This exists because the Accessibility API enumerates only the active Space.
/// See ``SpaceAwareWindowCounter``.
public protocol SpaceWindowLookup: AnyObject {
    /// How many windows each application has on Spaces that are not on screen,
    /// keyed by owning process.
    ///
    /// Applications with no such windows are absent rather than mapped to zero.
    func windowCountsOnInactiveSpaces() -> [pid_t: Int]
}

/// Answers ``SpaceWindowLookup`` by asking SkyLight which Space each window
/// belongs to.
///
/// `CGWindowList` is the only public API that sees across Spaces, but on its
/// own it cannot be counted: it reports menu bar strips, icon buffers, and the
/// leftover surfaces of windows that were closed, all at layer 0 and all
/// indistinguishable from a real window by size or by `kCGWindowIsOnscreen`.
/// Space membership is what separates them — a dead surface belongs to no
/// Space, a real window belongs to exactly the Space it sits on.
///
/// The three SkyLight functions used here are private, so they are resolved
/// with `dlsym` and the whole lookup reports nothing if any of them is missing.
/// A macOS release that withdraws them therefore costs Smart Quit its
/// cross-Space vision and nothing else — the Accessibility count still stands.
public final class SkyLightSpaceWindowLookup: SpaceWindowLookup {
    /// Every window the window server knows about, as `CGWindowList` dictionaries.
    typealias WindowListReader = () -> [[String: Any]]

    /// The Spaces currently on screen — one per attached display.
    typealias ActiveSpacesReader = () -> Set<Int>

    /// The Spaces a window belongs to, empty for a surface on no Space at all.
    typealias WindowSpacesReader = (Int) -> Set<Int>

    /// Only windows at this layer are ordinary application windows. Menus,
    /// the Dock, status items, and the desktop all live at other layers.
    static let normalWindowLayer = 0

    private let readWindowList: WindowListReader
    private let readActiveSpaces: ActiveSpacesReader
    private let readWindowSpaces: WindowSpacesReader

    init(
        readWindowList: @escaping WindowListReader,
        readActiveSpaces: @escaping ActiveSpacesReader,
        readWindowSpaces: @escaping WindowSpacesReader
    ) {
        self.readWindowList = readWindowList
        self.readActiveSpaces = readActiveSpaces
        self.readWindowSpaces = readWindowSpaces
    }

    /// Builds a lookup over the real window server, or one that reports nothing
    /// if SkyLight does not vend the symbols this needs.
    public convenience init() {
        guard let skyLight = SkyLight() else {
            Log.windows.notice("SkyLight unavailable — windows on other Spaces will not be seen")
            self.init(readWindowList: { [] }, readActiveSpaces: { [] }, readWindowSpaces: { _ in [] })
            return
        }
        self.init(
            readWindowList: Self.readWindowListViaCoreGraphics,
            readActiveSpaces: skyLight.activeSpaces,
            readWindowSpaces: skyLight.spaces(forWindow:)
        )
    }

    public func windowCountsOnInactiveSpaces() -> [pid_t: Int] {
        let activeSpaces = readActiveSpaces()
        guard !activeSpaces.isEmpty else { return [:] }

        var counts: [pid_t: Int] = [:]
        for window in readWindowList() {
            guard window[kCGWindowLayer as String] as? Int == Self.normalWindowLayer,
                  let pid = window[kCGWindowOwnerPID as String] as? pid_t,
                  let id = window[kCGWindowNumber as String] as? Int
            else { continue }

            // A surface belonging to no Space is a buffer, not a window. One
            // that shares a Space with the user is already visible to the
            // Accessibility count and must not be added to it twice.
            let spaces = readWindowSpaces(id)
            guard !spaces.isEmpty, spaces.isDisjoint(with: activeSpaces) else { continue }

            counts[pid, default: 0] += 1
        }
        return counts
    }

    // MARK: - Core Graphics

    private static func readWindowListViaCoreGraphics() -> [[String: Any]] {
        // .optionAll rather than .optionOnScreenOnly: a window on another Space
        // is by definition not on screen, which is the entire point here.
        CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] ?? []
    }
}
