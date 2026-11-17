import AppKit
import SwiftUI
import ViVuCore

/// Settings window (⌘,), docs/UI_SPEC.md §10: the standard macOS preferences layout — a toolbar of icons on
/// top, one grouped form per tab, the window resizing to each tab. Every change applies at once.
@MainActor
final class SettingsWindowController: NSWindowController {
    let associations: FileAssociations
    private let tabs = SettingsTabController()

    init(settings: Settings) {
        associations = FileAssociations(defaults: .standard)
        for tab in SettingsTab.allCases {
            let host = NSHostingController(rootView: SettingsPane(tab: tab, settings: settings, associations: associations))
            host.sizingOptions = [.preferredContentSize]
            host.title = tab.title
            let item = NSTabViewItem(viewController: host)
            item.identifier = tab.rawValue
            item.label = tab.title
            item.image = NSImage(systemSymbolName: tab.symbol, accessibilityDescription: tab.title)
            tabs.addTabViewItem(item)
        }
        tabs.tabStyle = .toolbar
        tabs.transitionOptions = [.allowUserInteraction]
        let window = NSWindow(contentViewController: tabs)
        window.styleMask = [.titled, .closable]
        window.toolbarStyle = .preference
        window.isReleasedWhenClosed = false
        super.init(window: window)
        tabs.fitWindow(animated: false)
        window.center()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func show(tab: SettingsTab? = nil) {
        if let tab, let index = SettingsTab.allCases.firstIndex(of: tab) { tabs.selectedTabViewItemIndex = index }
        associations.refresh()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }
}

/// Resizes the window to the selected tab's size, keeping its top edge where it is.
@MainActor
final class SettingsTabController: NSTabViewController {
    override func tabView(_ tabView: NSTabView, didSelect tabViewItem: NSTabViewItem?) {
        super.tabView(tabView, didSelect: tabViewItem)
        fitWindow(animated: view.window?.isVisible == true)
    }

    func fitWindow(animated: Bool) {
        guard let window = view.window, let item = tabViewItems[safe: selectedTabViewItemIndex],
              let child = item.viewController else { return }
        window.title = item.label
        let size = child.preferredContentSize == .zero ? child.view.fittingSize : child.preferredContentSize
        let content = window.frameRect(forContentRect: NSRect(origin: .zero, size: size))
        var frame = window.frame
        frame.origin.y += frame.height - content.height
        frame.size = content.size
        window.setFrame(frame, display: true, animate: animated)
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}

enum SettingsTab: String, CaseIterable, Identifiable {
    case general, display, controls, formats, performance
    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: String(localized: "Chung")
        case .display: String(localized: "Hiển thị")
        case .controls: String(localized: "Điều khiển")
        case .formats: String(localized: "Định dạng")
        case .performance: String(localized: "Hiệu năng")
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .display: "photo"
        case .controls: "hand.tap"
        case .formats: "doc.on.doc"
        case .performance: "speedometer"
        }
    }

    /// Content size of each tab, points. The forms are grouped (scrolling) lists, which have no natural height.
    var size: CGSize {
        switch self {
        case .general: CGSize(width: 520, height: 292)
        case .display: CGSize(width: 520, height: 584)
        case .controls: CGSize(width: 520, height: 180)
        case .formats: CGSize(width: 520, height: 560)
        case .performance: CGSize(width: 520, height: 252)
        }
    }
}

struct SettingsPane: View {
    let tab: SettingsTab
    @Bindable var settings: Settings
    let associations: FileAssociations

    var body: some View {
        Group {
            switch tab {
            case .general: GeneralPane(settings: settings)
            case .display: DisplayPane(settings: settings)
            case .controls: ControlsPane(settings: settings)
            case .formats: FormatsPane(associations: associations)
            case .performance: PerformancePane(settings: settings)
            }
        }
        .formStyle(.grouped)
        .frame(width: tab.size.width, height: tab.size.height)
    }
}

private struct GeneralPane: View {
    @Bindable var settings: Settings
    @State private var language = AppLanguage.chosen ?? ""
    private let initialLanguage = AppLanguage.chosen ?? ""

    var body: some View {
        Form {
            Section {
                Picker(String(localized: "Ngôn ngữ"), selection: $language) {
                    Text(String(localized: "Theo hệ thống")).tag("")
                    Divider()
                    ForEach(AppLanguage.all, id: \.self) { Text(AppLanguage.nativeName($0)).tag($0) }
                }
                .onChange(of: language) { _, new in AppLanguage.chosen = new.isEmpty ? nil : new }
            } footer: {
                if language != initialLanguage {
                    Text(String(localized: "Ngôn ngữ mới có hiệu lực khi mở lại ViVuView."))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Section {
                Picker(String(localized: "Sắp xếp ảnh trong thư mục"), selection: $settings.sortKey) {
                    Text(String(localized: "Tên (như Finder)")).tag(Settings.SortKey.name)
                    Text(String(localized: "Ngày sửa")).tag(Settings.SortKey.modified)
                    Text(String(localized: "Ngày chụp")).tag(Settings.SortKey.captured)
                    Text(String(localized: "Dung lượng")).tag(Settings.SortKey.size)
                }
                Toggle(String(localized: "Sắp xếp tăng dần"), isOn: $settings.sortAscending)
                Picker(String(localized: "Khi tới ảnh cuối"), selection: $settings.wrapAround) {
                    Text(String(localized: "Dừng lại")).tag(false)
                    Text(String(localized: "Quay vòng về đầu")).tag(true)
                }
            }
            Section {
                Toggle(String(localized: "Hỏi trước khi chuyển vào Thùng rác"), isOn: $settings.confirmTrash)
                Toggle(String(localized: "Thoát app khi đóng cửa sổ"), isOn: $settings.quitOnLastWindow)
            }
        }
        .toggleStyle(.switch)
    }
}

private struct DisplayPane: View {
    @Bindable var settings: Settings

    var body: some View {
        Form {
            Section {
                Picker(String(localized: "Kích thước 100%"), selection: $settings.renderUnit) {
                    Text("Point").tag(RenderUnit.point)
                    Text("Pixel").tag(RenderUnit.pixel)
                }
                .pickerStyle(.segmented)
                Picker(String(localized: "Khi mở ảnh"), selection: $settings.openSize) {
                    Text(String(localized: "Vừa màn hình, tối đa 100%")).tag(Settings.OpenSize.fitMax100)
                    Text(String(localized: "Luôn vừa màn hình")).tag(Settings.OpenSize.alwaysFit)
                    Text(String(localized: "Luôn 100%")).tag(Settings.OpenSize.always100)
                }
                Picker(String(localized: "Nền"), selection: $settings.background) {
                    Text(String(localized: "Đen")).tag(Settings.Background.black)
                    Text(String(localized: "Xám đậm")).tag(Settings.Background.darkGray)
                    Text(String(localized: "Xám")).tag(Settings.Background.gray)
                    Text(String(localized: "Xám nhạt")).tag(Settings.Background.lightGray)
                    Text(String(localized: "Nửa trong suốt")).tag(Settings.Background.translucent)
                    Text(String(localized: "Ô caro (ảnh trong suốt)")).tag(Settings.Background.checkerboard)
                }
                Picker(String(localized: "Status bar"), selection: $settings.statusBar) {
                    Text(String(localized: "Khi rê chuột")).tag(Settings.StatusBarMode.onHover)
                    Text(String(localized: "Luôn hiện")).tag(Settings.StatusBarMode.always)
                    Text(String(localized: "Không bao giờ")).tag(Settings.StatusBarMode.never)
                }
                Toggle(String(localized: "Click lên ảnh để ghim status bar"), isOn: $settings.clickPinsStatusBar)
                    .toggleStyle(.switch)
                    .disabled(settings.statusBar != .onHover)
            }
            Section {
                if OverlayBackground.supportsGlassStyles {
                    // Apple's two Liquid Glass variants (NSGlassEffectView.Style .regular / .clear).
                    Picker(String(localized: "Kính lỏng"), selection: $settings.barClearGlass) {
                        Text(String(localized: "Mờ")).tag(false)
                        Text(String(localized: "Trong")).tag(true)
                    }
                }
                LabeledContent(String(localized: "Độ tối")) {
                    HStack {
                        MarkedSlider(value: $settings.barTint, in: 0...0.8, mark: Settings.defaultBarTint)
                        Text(verbatim: "\(Int((settings.barTint * 100).rounded())) %").monospacedDigit().foregroundStyle(.secondary)
                            .frame(width: 52, alignment: .trailing)
                    }
                    .frame(width: 220)
                }
            } header: {
                Text(String(localized: "Thanh tiêu đề, status bar và các thanh nổi"))
            }
            Section {
                Picker(String(localized: "Hiệu ứng chuyển ảnh"), selection: $settings.transition) {
                    Text(String(localized: "Trượt + mờ")).tag(Settings.Transition.slideFade)
                    Text(String(localized: "Chỉ mờ")).tag(Settings.Transition.fade)
                    Text(String(localized: "Không")).tag(Settings.Transition.none)
                }
                LabeledContent(String(localized: "Thời lượng hiệu ứng")) {
                    HStack {
                        MarkedSlider(value: $settings.transitionMilliseconds, in: 0...300, mark: Settings.defaultTransitionMilliseconds)
                        Text("\(Int(settings.transitionMilliseconds)) ms").monospacedDigit().foregroundStyle(.secondary)
                            .frame(width: 52, alignment: .trailing)
                    }
                    .frame(width: 220)
                }
            }
            Section {
                Picker(String(localized: "Filmstrip"), selection: $settings.filmstrip) {
                    Text(String(localized: "Tự ẩn")).tag(Settings.FilmstripMode.autoHide)
                    Text(String(localized: "Luôn hiện")).tag(Settings.FilmstripMode.always)
                }
                Picker(String(localized: "Cỡ thumbnail filmstrip"), selection: $settings.filmstripThumb) {
                    Text(String(localized: "Nhỏ")).tag(Settings.ThumbSize.small)
                    Text(String(localized: "thumbSize.medium", defaultValue: "Vừa", comment: "Medium thumbnail size")).tag(Settings.ThumbSize.medium)
                    Text(String(localized: "Lớn")).tag(Settings.ThumbSize.large)
                }
                LabeledContent(String(localized: "Độ rộng cột Gallery")) {
                    HStack {
                        MarkedSlider(value: $settings.galleryColumnWidth, in: 120...480, mark: Settings.defaultGalleryColumnWidth)
                        Text("\(Int(settings.galleryColumnWidth)) pt").monospacedDigit().foregroundStyle(.secondary)
                            .frame(width: 52, alignment: .trailing)
                    }
                    .frame(width: 220)
                }
            }
        }
    }
}

private struct ControlsPane: View {
    @Bindable var settings: Settings

    var body: some View {
        Form {
            Section {
                Toggle(String(localized: "Đảo chiều vuốt chuyển ảnh"), isOn: $settings.invertSwipe)
                Picker(String(localized: "Bước zoom bằng phím"), selection: $settings.zoomStep) {
                    ForEach([1.1, 1.25, 1.5, 2.0], id: \.self) { Text(String(format: "×%g", $0)).tag($0) }
                }
                Toggle(String(localized: "Giữ mức zoom khi chuyển ảnh"), isOn: $settings.keepZoom)
            } footer: {
                HStack {
                    Spacer()
                    Button(String(localized: "Xem phím tắt…")) { ShortcutsPanel.shared.toggle(over: nil) }
                }
            }
        }
        .toggleStyle(.switch)
    }
}

private struct PerformancePane: View {
    @Bindable var settings: Settings

    var body: some View {
        Form {
            Section {
                Picker(String(localized: "Số ảnh nạp trước mỗi phía"), selection: $settings.preloadEachSide) {
                    ForEach(1...4, id: \.self) { Text("\($0)").tag($0) }
                }
                Picker(String(localized: "Bộ nhớ cho thumbnail"), selection: $settings.thumbnailMemoryMB) {
                    Text(String(localized: "Tự động") + " (\(Settings.automaticThumbnailMemoryMB) MB)").tag(0)
                    Divider()
                    Text("128 MB").tag(128)
                    Text("256 MB").tag(256)
                    Text("384 MB").tag(384)
                    Text("768 MB").tag(768)
                }
                Picker(String(localized: "Bộ nhớ cho ảnh lớn (tile)"), selection: $settings.tileMemoryMB) {
                    ForEach([256, 512, 1024, 2048], id: \.self) { Text("\($0) MB").tag($0) }
                }
            } footer: {
                Text(String(localized: "ViVuView không lưu thumbnail hay bộ nhớ đệm ra đĩa."))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section {
                Picker("RAW", selection: $settings.rawMode) {
                    Text(String(localized: "Dùng ảnh xem trước nhúng")).tag(Settings.RawMode.embeddedPreview)
                    Text(String(localized: "Luôn xử lý RAW đầy đủ")).tag(Settings.RawMode.fullRaw)
                }
            }
        }
    }
}

/// Formats tab (docs/UI_SPEC.md §10.1).
private struct FormatsPane: View {
    let associations: FileAssociations

    var body: some View {
        Form {
            Section {
                Text(String(localized: "Mở bằng ViVuView khi double-click trong Finder:"))
                if !associations.canAssociate {
                    Label(String(localized: "Hãy chuyển ViVuView vào thư mục Applications trước khi gắn định dạng."),
                          systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
                if !associations.message.isEmpty {
                    Label(associations.message, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                }
            }
            ForEach(ImageFormat.Group.allCases, id: \.self) { group in
                Section {
                    ForEach(associations.rows.filter { $0.format.group == group }) { row in
                        Toggle(isOn: Binding(get: { row.ours }, set: { on in
                            Task { await associations.set([row.format], on: on) }
                        })) {
                            // One line per format so a whole group fits without scrolling.
                            HStack(spacing: 8) {
                                Text(row.format.name)
                                Text(detail(row)).font(.caption).foregroundStyle(.secondary)
                                    .lineLimit(1).truncationMode(.middle)
                            }
                        }
                    }
                } header: {
                    HStack {
                        Text(title(group))
                        Spacer()
                        Button(String(localized: "Chọn cả nhóm")) {
                            Task { await associations.set(FormatCatalog.all.filter { $0.group == group }, on: true) }
                        }
                        .buttonStyle(.link)
                        .font(.caption)
                    }
                }
            }
            Section {
                HStack {
                    Button(String(localized: "Chọn tất cả")) { Task { await associations.set(FormatCatalog.all, on: true) } }
                    Button(String(localized: "Bỏ chọn tất cả")) { Task { await associations.set(FormatCatalog.all, on: false) } }
                }
            } footer: {
                Text(String(localized: "Bạn cũng có thể đổi trong Finder: chọn file → Get Info → Open with → Change All."))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .toggleStyle(.switch)
        .controlSize(.small)
        .disabled(!associations.canAssociate)
    }

    private func detail(_ row: FileAssociations.Row) -> String {
        let extensions = row.format.extensions.map { "." + $0 }.joined(separator: " ")
        let handler = row.ours ? "ViVuView" : row.handlerName
        return "\(extensions) · \(handler)"
    }

    private func title(_ group: ImageFormat.Group) -> String {
        switch group {
        case .common: String(localized: "Ảnh thông dụng")
        case .raw: String(localized: "RAW máy ảnh")
        case .special: String(localized: "Chuyên dụng")
        }
    }
}

/// A slider with a small tick under the track at the default value; the knob snaps to it when dragged close.
struct MarkedSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let mark: Double

    /// Distance from the track ends to where the knob's center stops (half the knob's width).
    private static let knobInset: CGFloat = 10
    private static let snapFraction = 0.02

    init(value: Binding<Double>, in range: ClosedRange<Double>, mark: Double) {
        _value = value
        self.range = range
        self.mark = mark
    }

    var body: some View {
        let span = range.upperBound - range.lowerBound
        let snapping = Binding<Double>(
            get: { value },
            set: { value = abs($0 - mark) < span * Self.snapFraction ? mark : $0 })
        Slider(value: snapping, in: range)
            .overlay(alignment: .bottomLeading) {
                GeometryReader { proxy in
                    let travel = proxy.size.width - 2 * Self.knobInset
                    Capsule()
                        .fill(.tertiary)
                        .frame(width: 2, height: 5)
                        .position(x: Self.knobInset + travel * (mark - range.lowerBound) / span, y: proxy.size.height + 6)
                }
                .allowsHitTesting(false)
            }
    }
}
