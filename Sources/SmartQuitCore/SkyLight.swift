// SPDX-FileCopyrightText: 2026 Aswin Murali
// SPDX-License-Identifier: GPL-3.0-only

import CoreGraphics
import Foundation

/// The handful of SkyLight functions that expose Mission Control Spaces.
///
/// Nothing public tells you which Space a window is on, nor whether a surface
/// the window server is holding is actually placed on screen. SkyLight is the
/// private framework behind the window server, and these four functions are the
/// ones every window manager on macOS relies on for this. They are resolved at
/// run time rather than linked, so a macOS release that removes or renames one
/// of them leaves ``SkyLightSpaceWindowLookup`` reporting nothing instead of
/// failing to launch.
///
/// Smart Quit is distributed as a signed disk image, not through the App Store,
/// so use of a private framework carries no review consequence. It does carry a
/// maintenance one, which is why the surface is kept to three calls and why
/// every one of them is optional.
struct SkyLight {
    private typealias MainConnectionIDFn = @convention(c) () -> Int32
    private typealias CopyManagedDisplaySpacesFn = @convention(c) (Int32) -> Unmanaged<CFArray>?
    private typealias CopySpacesForWindowsFn = @convention(c) (Int32, Int32, CFArray) -> Unmanaged<CFArray>?

    /// Note the out-parameter. The two-argument `(Int32, UInt32) -> Bool` form
    /// this function is usually quoted as does not match the real symbol and
    /// crashes the process on call.
    private typealias WindowIsOrderedInFn =
        @convention(c) (Int32, UInt32, UnsafeMutablePointer<Bool>) -> Int32

    /// Asks for every Space a window is on, rather than only the current one.
    private static let allSpacesMask: Int32 = 0x7

    private static let path =
        "/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight"

    private let connection: Int32
    private let copyManagedDisplaySpaces: CopyManagedDisplaySpacesFn
    private let copySpacesForWindows: CopySpacesForWindowsFn
    private let windowIsOrderedIn: WindowIsOrderedInFn

    /// Returns `nil` unless every symbol needed is present.
    init?() {
        guard let handle = dlopen(Self.path, RTLD_LAZY),
              let mainConnection = dlsym(handle, "SLSMainConnectionID"),
              let displaySpaces = dlsym(handle, "SLSCopyManagedDisplaySpaces"),
              let windowSpaces = dlsym(handle, "SLSCopySpacesForWindows"),
              let orderedIn = dlsym(handle, "SLSWindowIsOrderedIn")
        else { return nil }
        // The handle is deliberately never closed: the function pointers below
        // outlive this initialiser and would dangle if the image were unloaded.

        connection = unsafeBitCast(mainConnection, to: MainConnectionIDFn.self)()
        copyManagedDisplaySpaces = unsafeBitCast(displaySpaces, to: CopyManagedDisplaySpacesFn.self)
        copySpacesForWindows = unsafeBitCast(windowSpaces, to: CopySpacesForWindowsFn.self)
        windowIsOrderedIn = unsafeBitCast(orderedIn, to: WindowIsOrderedInFn.self)
    }

    /// The Space currently shown on each display.
    ///
    /// Every display has its own current Space, so a window is only "elsewhere"
    /// when it is on none of them.
    func activeSpaces() -> Set<Int> {
        guard let displays = copyManagedDisplaySpaces(connection)?
            .takeRetainedValue() as? [[String: Any]] else { return [] }

        return Set(displays.compactMap {
            ($0["Current Space"] as? [String: Any])?["ManagedSpaceID"] as? Int
        })
    }

    /// The Spaces a window belongs to.
    ///
    /// Empty for a surface the window server holds but has not placed on any
    /// Space — a shadow, an icon buffer, or the remains of a closed window. A
    /// window shown on every Space reports more than one.
    func spaces(forWindow id: CGWindowID) -> Set<Int> {
        guard let spaces = copySpacesForWindows(connection, Self.allSpacesMask, [id] as CFArray)?
            .takeRetainedValue() as? [Int] else { return [] }
        return Set(spaces)
    }

    /// Whether the window server has actually placed this surface on its Space.
    ///
    /// This is what separates a window from the surface a window left behind.
    /// It is not the same question as "is it visible": a window sitting on
    /// another desktop is ordered in and reports `true`, which is precisely why
    /// this is asked rather than `kCGWindowIsOnscreen`.
    func isOrderedIn(window id: CGWindowID) -> Bool {
        var result = false
        guard windowIsOrderedIn(connection, id, &result) == 0 else { return false }
        return result
    }
}
