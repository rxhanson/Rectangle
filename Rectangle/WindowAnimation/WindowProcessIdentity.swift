import Cocoa
import Darwin

enum WindowProcessIdentity {
    /// Launch Services may omit launchDate for apps started by an executable.
    /// Kernel start time still distinguishes a reused PID without an AX query.
    static func launchTime(for pid: pid_t) -> TimeInterval? {
        var info = proc_bsdinfo()
        if proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, Int32(MemoryLayout<proc_bsdinfo>.size)) == MemoryLayout<proc_bsdinfo>.size {
            return Date(timeIntervalSince1970: Double(info.pbi_start_tvsec) + Double(info.pbi_start_tvusec) / 1_000_000)
                .timeIntervalSinceReferenceDate
        }
        return NSRunningApplication(processIdentifier: pid)?.launchDate?.timeIntervalSinceReferenceDate
    }
}
