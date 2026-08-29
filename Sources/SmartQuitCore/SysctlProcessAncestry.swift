import Darwin
import Foundation

/// Reads process parentage from the kernel.
///
/// `sysctl(KERN_PROC_PID)` is the only public way to ask who launched a
/// process. It needs no entitlement and works for processes owned by other
/// users, where `proc_pidinfo` would not.
public final class SysctlProcessAncestry: ProcessAncestry {
    public init() {}

    public func parent(of pid: pid_t) -> pid_t? {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride

        let result = sysctl(&mib, u_int(mib.count), &info, &size, nil, 0)
        // A size of zero means the process died between listing and asking.
        guard result == 0, size > 0 else { return nil }

        let parent = info.kp_eproc.e_ppid
        return parent > 0 ? parent : nil
    }
}
