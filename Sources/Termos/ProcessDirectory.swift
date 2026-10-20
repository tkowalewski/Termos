import Darwin
import Foundation

enum ProcessDirectory {
    /// Reads the current working directory of a process via libproc.
    /// Works for any shell without shell integration.
    static func currentDirectory(of pid: pid_t) -> URL? {
        guard pid > 0 else { return nil }

        var info = proc_vnodepathinfo()
        let size = Int32(MemoryLayout<proc_vnodepathinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &info, size) == size else { return nil }

        let path = withUnsafeBytes(of: &info.pvi_cdir.vip_path) { buffer in
            String(cString: buffer.bindMemory(to: CChar.self).baseAddress!)
        }
        guard !path.isEmpty else { return nil }
        return URL(fileURLWithPath: path, isDirectory: true)
    }

    /// Accepts both the `file://host/path` form of OSC 7 and a bare path.
    static func url(fromOSC7 value: String) -> URL? {
        if let url = URL(string: value), url.isFileURL {
            return URL(fileURLWithPath: url.path, isDirectory: true)
        }
        guard value.hasPrefix("/") else { return nil }
        return URL(fileURLWithPath: value, isDirectory: true)
    }
}
