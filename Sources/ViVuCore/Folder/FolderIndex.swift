import Foundation

/// One image file in a folder, with what sorting needs. Never reads file contents (docs/TECH_SPEC.md §5.1).
public struct FolderEntry: Hashable, Sendable {
    public let url: URL
    public let name: String
    public let fileSize: Int64
    public let modified: Date
    public let created: Date

    public init(url: URL, fileSize: Int64, modified: Date, created: Date) {
        self.url = url
        self.name = url.lastPathComponent
        self.fileSize = fileSize
        self.modified = modified
        self.created = created
    }
}

public enum FolderSort: String, Sendable, CaseIterable {
    /// File name like Finder (numbers compared as numbers).
    case name
    case modified
    /// Capture date; uses the file creation date, which cameras and phones set to the capture time.
    case captured
    case size
}

/// The image files of one folder, sorted; scanned off the main thread.
public enum FolderIndex {
    static let keys: [URLResourceKey] = [.fileSizeKey, .contentModificationDateKey, .creationDateKey,
                                         .isRegularFileKey, .isHiddenKey]

    /// Lists and sorts the image files in `folder`. Blocking: call from a background queue.
    public static func scan(_ folder: URL, sort: FolderSort, ascending: Bool) throws -> [FolderEntry] {
        let urls = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: keys,
                                                               options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants])
        var entries: [FolderEntry] = []
        entries.reserveCapacity(urls.count)
        for url in urls where FormatCatalog.isImage(url) {
            let values = try? url.resourceValues(forKeys: Set(keys))
            guard values?.isRegularFile ?? true else { continue }
            entries.append(FolderEntry(url: url, fileSize: Int64(values?.fileSize ?? 0),
                                       modified: values?.contentModificationDate ?? .distantPast,
                                       created: values?.creationDate ?? values?.contentModificationDate ?? .distantPast))
        }
        return sorted(entries, by: sort, ascending: ascending)
    }

    public static func sorted(_ entries: [FolderEntry], by sort: FolderSort, ascending: Bool) -> [FolderEntry] {
        let byName: (FolderEntry, FolderEntry) -> Bool = { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        let result: [FolderEntry]
        switch sort {
        case .name: result = entries.sorted(by: byName)
        case .modified: result = entries.sorted { $0.modified == $1.modified ? byName($0, $1) : $0.modified < $1.modified }
        case .captured: result = entries.sorted { $0.created == $1.created ? byName($0, $1) : $0.created < $1.created }
        case .size: result = entries.sorted { $0.fileSize == $1.fileSize ? byName($0, $1) : $0.fileSize < $1.fileSize }
        }
        return ascending ? result : result.reversed()
    }
}

/// Watches a folder for added, removed or renamed files; calls back (debounced) on the main actor.
public final class FolderWatcher: @unchecked Sendable {
    // Sendable: `source` is created once and only cancelled from deinit.
    private let source: DispatchSourceFileSystemObject

    public init?(folder: URL, onChange: @escaping @MainActor @Sendable () -> Void) {
        let fd = open(folder.path, O_EVTONLY)
        guard fd >= 0 else { return nil }
        source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .rename, .delete],
                                                           queue: .global(qos: .utility))
        let debounce = Debouncer(delay: 0.3)
        source.setEventHandler { debounce.call { Task { @MainActor in onChange() } } }
        source.setCancelHandler { close(fd) }
        source.resume()
    }

    deinit { source.cancel() }
}

final class Debouncer: @unchecked Sendable {
    // Sendable: `pending` is only touched under `lock`.
    private let delay: TimeInterval
    private let lock = NSLock()
    private var pending: DispatchWorkItem?

    init(delay: TimeInterval) { self.delay = delay }

    func call(_ action: @escaping @Sendable () -> Void) {
        let item = DispatchWorkItem(block: action)
        lock.withLock {
            pending?.cancel()
            pending = item
        }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + delay, execute: item)
    }
}
