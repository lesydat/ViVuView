import AppKit
import UniformTypeIdentifiers
import ViVuCore

/// Which formats open with ViVuView when double-clicked in Finder (docs/UI_SPEC.md §10.1, TECH_SPEC §9.1).
/// The checkboxes reflect the system's real defaults, read each time; nothing is stored except the app that
/// had a type before ViVuView claimed it, so unticking can give it back.
@MainActor @Observable
final class FileAssociations {
    struct Row: Identifiable {
        let format: ImageFormat
        var ours: Bool
        var handlerName: String
        var id: String { format.id }
    }

    private(set) var rows: [Row] = []
    var message = ""
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored let ourPath = Bundle.main.bundleURL.standardizedFileURL.path

    init(defaults: UserDefaults) { self.defaults = defaults }

    /// Linking only makes sense from a packaged app at a stable place (not the build folder).
    var canAssociate: Bool {
        Bundle.main.bundleURL.pathExtension == "app" && !ourPath.contains("/build/") && !ourPath.contains("/.build/")
    }

    func refresh() {
        rows = FormatCatalog.all.map { format in
            let handlers = format.utis.compactMap { UTType($0) }.map { NSWorkspace.shared.urlForApplication(toOpen: $0) }
            let first = handlers.compactMap { $0 }.first
            let ours = !handlers.isEmpty && handlers.allSatisfy { $0?.standardizedFileURL.path == ourPath }
            let name = first.map { FileManager.default.displayName(atPath: $0.path).replacingOccurrences(of: ".app", with: "") } ?? "—"
            return Row(format: format, ours: ours, handlerName: name)
        }
    }

    func set(_ formats: [ImageFormat], on: Bool) async {
        guard canAssociate else {
            message = String(localized: "Hãy chuyển ViVuView vào thư mục Applications trước khi gắn định dạng.")
            return
        }
        let utis = formats.flatMap(\.utis)
        var current: [String: String?] = [:]
        for uti in utis {
            current[uti] = UTType(uti).flatMap { NSWorkspace.shared.urlForApplication(toOpen: $0) }?.standardizedFileURL.path
        }
        let wantedNow = Set(rows.filter(\.ours).flatMap(\.format.utis))
        let wanted = on ? wantedNow.union(utis) : wantedNow.subtracting(utis)
        var remembered: [String: String] = [:]
        for uti in utis { if let path = defaults.string(forKey: "previousHandler.\(uti)") { remembered[uti] = path } }
        let steps = FileAssociationPlanner.plan(utis: utis, current: current, ours: ourPath, wanted: wanted, remembered: remembered)
        var failures = 0
        for step in steps {
            do {
                switch step {
                case .claim(let uti, let previous):
                    guard let type = UTType(uti) else { continue }
                    if let previous { defaults.set(previous, forKey: "previousHandler.\(uti)") }
                    try await NSWorkspace.shared.setDefaultApplication(at: Bundle.main.bundleURL, toOpen: type)
                case .release(let uti, let to):
                    guard let type = UTType(uti) else { continue }
                    try await NSWorkspace.shared.setDefaultApplication(at: URL(fileURLWithPath: to), toOpen: type)
                    defaults.removeObject(forKey: "previousHandler.\(uti)")
                }
            } catch {
                failures += 1   // e.g. the user declined the system confirmation
            }
        }
        message = failures == 0 ? "" : String(localized: "\(failures) loại không đổi được (có thể bạn đã từ chối hộp thoại hệ thống).")
        refresh()
    }
}
