import AppKit
import MapKit
import SwiftUI
import ViVuCore

/// What the info panel shows (docs/UI_SPEC.md §9). Updated by the viewer controller.
@MainActor @Observable
final class InfoModel {
    var info: ImageInfo?
    var histogram: Histogram?
    var fileName = ""
    var zoom = ""
    var shownResolution = ""
    var detail = ""
    var position = ""
}

/// The panel content (SwiftUI): histogram, General, Camera, Location, Display; every value selectable.
struct InfoPanelView: View {
    let model: InfoModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let histogram = model.histogram {
                    HistogramView(histogram: histogram).frame(height: 80)
                }
                if let info = model.info {
                    section(String(localized: "Chung")) {
                        row(String(localized: "Tên"), info.url.lastPathComponent)
                        folderRow(info.url)
                        row(String(localized: "Loại"), info.typeName)
                        row(String(localized: "Kích thước"), "\(info.pixelSize.width) × \(info.pixelSize.height) (\(String(format: "%.1f", info.megapixels)) MP)")
                        row(String(localized: "Dung lượng"), Format.bytes(info.fileSize))
                        if let dpi = info.dpi { row("DPI", "\(Int(dpi))") }
                        if let depth = info.bitDepth { row(String(localized: "Độ sâu bit"), "\(depth)") }
                        if let profile = info.profileName { row(String(localized: "Hồ sơ màu"), profile) }
                        if let taken = info.dateTaken { row(String(localized: "Ngày chụp"), taken.formatted(date: .abbreviated, time: .standard)) }
                        if let modified = info.dateModified { row(String(localized: "Ngày sửa"), modified.formatted(date: .abbreviated, time: .standard)) }
                    }
                    if info.camera != nil || info.exposureSummary != nil {
                        section(String(localized: "Máy ảnh")) {
                            if let camera = info.camera { row(String(localized: "Máy"), camera) }
                            if let lens = info.lens { row(String(localized: "Ống kính"), lens) }
                            if let f = info.focalLength { row(String(localized: "Tiêu cự"), "\(Self.trim(f)) mm") }
                            if let n = info.fNumber { row(String(localized: "Khẩu độ"), "ƒ/\(Self.trim(n))") }
                            if let t = info.exposureTime { row(String(localized: "Tốc độ"), ImageInfo.shutter(t)) }
                            if let iso = info.iso { row("ISO", "\(iso)") }
                            if let bias = info.exposureBias { row(String(localized: "Bù sáng"), String(format: "%+.1f EV", bias)) }
                            if let flash = info.flashFired { row("Flash", flash ? String(localized: "Có") : String(localized: "Không")) }
                            if let wb = info.whiteBalanceAuto { row(String(localized: "Cân bằng trắng"), wb ? String(localized: "Tự động") : String(localized: "Thủ công")) }
                        }
                    }
                    if let lat = info.latitude, let lon = info.longitude {
                        section(String(localized: "Vị trí")) {
                            LocationView(latitude: lat, longitude: lon).frame(height: 160).clipShape(RoundedRectangle(cornerRadius: 6))
                            row(String(localized: "Toạ độ"), String(format: "%.5f, %.5f", lat, lon))
                        }
                    }
                } else {
                    Text(model.fileName.isEmpty ? String(localized: "Không có ảnh") : model.fileName)
                        .foregroundStyle(.secondary)
                }
                section(String(localized: "Hiển thị")) {
                    if !model.position.isEmpty { row(String(localized: "Vị trí"), model.position) }
                    row(String(localized: "Zoom"), model.zoom)
                    if !model.shownResolution.isEmpty { row(String(localized: "Đang hiển thị"), model.shownResolution) }
                    if !model.detail.isEmpty { row(String(localized: "Chi tiết"), model.detail) }
                    if let frames = model.info?.frameCount, frames > 1 { row(String(localized: "Số khung"), "\(frames)") }
                }
            }
            .padding(14)
        }
        .font(.system(size: 11))
        .environment(\.colorScheme, .dark)
    }

    static func trim(_ v: Double) -> String { v == v.rounded() ? "\(Int(v))" : String(format: "%.1f", v) }

    @ViewBuilder
    private func section<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
            content()
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label).foregroundStyle(.secondary).frame(width: 82, alignment: .leading)
            Text(value).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func folderRow(_ url: URL) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(String(localized: "Thư mục")).foregroundStyle(.secondary).frame(width: 82, alignment: .leading)
            Button((url.deletingLastPathComponent().path as NSString).abbreviatingWithTildeInPath) {
                NSWorkspace.shared.activateFileViewerSelecting([url])
            }
            .buttonStyle(.link)
            .lineLimit(2)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct HistogramView: View {
    let histogram: Histogram

    var body: some View {
        Canvas { context, size in
            let peak = Double(max(histogram.peak, 1))
            func path(_ bins: [UInt32]) -> Path {
                var p = Path()
                p.move(to: CGPoint(x: 0, y: size.height))
                for (i, v) in bins.enumerated() {
                    let x = Double(i) / 255 * size.width
                    p.addLine(to: CGPoint(x: x, y: size.height - min(1, Double(v) / peak) * size.height))
                }
                p.addLine(to: CGPoint(x: size.width, y: size.height))
                p.closeSubpath()
                return p
            }
            context.blendMode = .plusLighter
            context.fill(path(histogram.red), with: .color(.red.opacity(0.55)))
            context.fill(path(histogram.green), with: .color(.green.opacity(0.55)))
            context.fill(path(histogram.blue), with: .color(.blue.opacity(0.6)))
            context.blendMode = .normal
            context.stroke(path(histogram.luma), with: .color(.white.opacity(0.7)), lineWidth: 1)
        }
        .background(Color.black.opacity(0.25))
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}

struct LocationView: View {
    let latitude: Double
    let longitude: Double

    var body: some View {
        let coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        Map(initialPosition: .region(MKCoordinateRegion(center: coordinate, latitudinalMeters: 3000, longitudinalMeters: 3000))) {
            Marker("", coordinate: coordinate)
        }
        .onTapGesture {
            let item = MKMapItem(placemark: MKPlacemark(coordinate: coordinate))
            item.openInMaps()
        }
    }
}

/// The info panel container: a child window glued to the viewer window's side (docs/UI_SPEC.md §9).
@MainActor
final class InfoPanelWindow: NSPanel {
    static let width: CGFloat = 280
    let model: InfoModel
    let host: NSView

    init(model: InfoModel) {
        self.model = model
        let hosting = NSHostingView(rootView: InfoPanelView(model: model))
        host = OverlayBackground.make(content: hosting)
        super.init(contentRect: NSRect(x: 0, y: 0, width: Self.width, height: 400),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isReleasedWhenClosed = false
        becomesKeyOnlyIfNeeded = true
        hidesOnDeactivate = false
        contentView = host
        host.wantsLayer = true
        host.layer?.cornerRadius = 10
        host.layer?.masksToBounds = true
    }

    override var canBecomeKey: Bool { false }

    /// Places the panel next to `frame` (right side, or left when the screen has no room).
    func place(beside frame: CGRect, on screen: NSScreen?) {
        let visible = screen?.visibleFrame ?? frame
        let height = max(360, frame.height)
        var x = frame.maxX + 8
        if x + Self.width > visible.maxX { x = frame.minX - 8 - Self.width }
        x = min(max(x, visible.minX), visible.maxX - Self.width)
        let y = min(max(frame.maxY - height, visible.minY), visible.maxY - height)
        setFrame(CGRect(x: x, y: y, width: Self.width, height: min(height, visible.height)), display: true)
    }
}
