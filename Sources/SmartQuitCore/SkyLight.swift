// SPDX-FileCopyrightText: 2026 Aswin Murali
// SPDX-License-Identifier: GPL-3.0-only

import Foundation

/// The handful of SkyLight functions that expose Mission Control Spaces.
///
/// Nothing public tells you which Space a window is on. SkyLight is the private
/// framework behind the window server, and these three functions are the ones
/// every window manager on macOS relies on for this. They are resolved at run
/// time rather than linked, so a macOS release that removes or renames one of
/// them leaves ``SkyLightSpaceWindowLookup`` reporting nothing instead of
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

    /// Asks for every Space a window is on, rather than only the current one.
    private static let allSpacesMask: Int32 = 0x7

    private static let path =
        "/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight"

    private let connection: Int32
    private let copyManagedDisplaySpaces: CopyManagedDisplaySpacesFn
    private let copySpacesForWindows: CopySpacesForWindowsFn

    /// Returns `nil` unless every symbol needed is present.
    init?() {
        guard let handle = dlopen(Self.path, RTLD_LAZY),
              let mainConnection = dlsym(handle, "SLSMainConnectionID"),
              let displaySpaces = dlsym(handle, "SLSCopyManagedDisplaySpaces"),
              let windowSpaces = dlsym(handle, "SLSCopySpacesForWindows")
        else { return nil }

        connection = unsafeBitCast(mainConnection, to: MainConnectionIDFn.self)()
        copyManagedDisplaySpaces = unsafeBitCast(displaySpaces, to: CopyManagedDisplaySpacesFn.self)
        copySpacesForWindows = unsafeBitCast(windowSpaces, to: CopySpacesForWindowsFn.self)
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
    func spaces(forWindow id: Int) -> Set<Int> {
        guard let spaces = copySpacesForWindows(connection, Self.allSpacesMask, [id] as CFArray)?
            .takeRetainedValue() as? [Int] else { return [] }
        return Set(spaces)
    }
}
