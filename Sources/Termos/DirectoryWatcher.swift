import CoreServices
import Foundation

/// Watches a directory tree with FSEvents and reports the directories that changed.
final class DirectoryWatcher {
    /// Changed directory paths (without a trailing slash), and whether everything must be rescanned.
    typealias Handler = (_ paths: [String], _ mustRescan: Bool) -> Void

    private var stream: FSEventStreamRef?
    private let handler: Handler

    init(url: URL, latency: TimeInterval = 0.3, handler: @escaping Handler) {
        self.handler = handler

        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil, release: nil, copyDescription: nil
        )
        let callback: FSEventStreamCallback = { _, info, count, rawPaths, flags, _ in
            guard let info else { return }
            let watcher = Unmanaged<DirectoryWatcher>.fromOpaque(info).takeUnretainedValue()
            let paths = (Unmanaged<CFArray>.fromOpaque(rawPaths).takeUnretainedValue() as? [String] ?? [])
                .map { $0.count > 1 && $0.hasSuffix("/") ? String($0.dropLast()) : $0 }
            let rescanFlags = UInt32(kFSEventStreamEventFlagMustScanSubDirs | kFSEventStreamEventFlagRootChanged)
            let mustRescan = (0..<count).contains { flags[$0] & rescanFlags != 0 }
            watcher.handler(paths, mustRescan)
        }

        let flags = FSEventStreamCreateFlags(
            kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagWatchRoot
        )
        guard let stream = FSEventStreamCreate(
            nil, callback, &context, [url.path] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow), latency, flags
        ) else { return }

        self.stream = stream
        FSEventStreamSetDispatchQueue(stream, .main)
        FSEventStreamStart(stream)
    }

    deinit {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
    }
}
