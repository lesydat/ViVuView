import AppKit
import SwiftUI
import ViVuCore

/// Settings window (⌘,), docs/UI_SPEC.md §10: five tabs, only the options that matter, every change applies at once.
@MainActor
final class SettingsWindowController: NSWindowController {
    let associations: FileAssociations
    private let tabs: SettingsTabs

    init(settings: Settings) {
        associations = FileAssociations(defaults: .standard)
        tabs = SettingsTabs()
        let view = SettingsView(settings: settings, associations: associations, tabs: tabs)
        let hosting = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: hosting)
        window.title = String(localized: "Cài đặt ViVuView")
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.setContentSize(NSSize(width: 560, height: 520))
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.center()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func show(tab: SettingsTab? = nil) {
        if let tab { tabs.selected = tab }
        associations.refresh()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }
}

enum SettingsTab: String, CaseIterable, Identifiable {
    case general, display, controls, formats, performance
    var id: String { rawValue }
}

@MainActor @Observable
final class SettingsTabs {
    var selected: SettingsTab = .general
}

struct SettingsView: View {
    @Bindable var settings: Settings
    let associations: FileAssociations
    @Bindable var tabs: SettingsTabs

    var body: some View {
        TabView(selection: $tabs.selected) {
            general.tabItem { Label(String(localized: "Chung"), systemImage: "gearshape") }.tag(SettingsTab.general)
            display.tabItem { Label(String(localized: "Hiển thị"), systemImage: "photo") }.tag(SettingsTab.display)
            controls.tabItem { Label(String(localized: "Điều khiển"), systemImage: "hand.tap") }.tag(SettingsTab.controls)
            FormatsTab(associations: associations).tabItem { Label(String(localized: "Định dạng"), systemImage: "doc.on.doc") }
                .tag(SettingsTab.formats)
            performance.tabItem { Label(String(localized: "Hiệu năng"), systemImage: "speedometer") }.tag(SettingsTab.performance)
        }
        .frame(width: 560, height: 520)
    }

    private var general: some View {
        Form {
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
            Toggle(String(localized: "Hỏi trước khi chuyển vào Thùng rác"), isOn: $settings.confirmTrash)
            Toggle(String(localized: "Thoát app khi đóng cửa sổ"), isOn: $settings.quitOnLastWindow)
        }
        .formStyle(.grouped)
    }

    private var display: some View {
        Form {
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
                Text(String(localized: "Ô caro (ảnh trong suốt)")).tag(Settings.Background.checkerboard)
            }
            Picker(String(localized: "Status bar"), selection: $settings.statusBar) {
                Text(String(localized: "Khi rê chuột")).tag(Settings.StatusBarMode.onHover)
                Text(String(localized: "Luôn hiện")).tag(Settings.StatusBarMode.always)
                Text(String(localized: "Không bao giờ")).tag(Settings.StatusBarMode.never)
            }
            Picker(String(localized: "Hiệu ứng chuyển ảnh"), selection: $settings.transition) {
                Text(String(localized: "Trượt + mờ")).tag(Settings.Transition.slideFade)
                Text(String(localized: "Chỉ mờ")).tag(Settings.Transition.fade)
                Text(String(localized: "Không")).tag(Settings.Transition.none)
            }
            LabeledContent(String(localized: "Thời lượng hiệu ứng")) {
                HStack {
                    Slider(value: $settings.transitionMilliseconds, in: 0...300)
                    Text("\(Int(settings.transitionMilliseconds)) ms").monospacedDigit().frame(width: 56, alignment: .trailing)
                }
            }
            Picker(String(localized: "Filmstrip"), selection: $settings.filmstrip) {
                Text(String(localized: "Tự ẩn")).tag(Settings.FilmstripMode.autoHide)
                Text(String(localized: "Luôn hiện")).tag(Settings.FilmstripMode.always)
            }
            Picker(String(localized: "Cỡ thumbnail filmstrip"), selection: $settings.filmstripThumb) {
                Text(String(localized: "Nhỏ")).tag(Settings.ThumbSize.small)
                Text(String(localized: "Vừa")).tag(Settings.ThumbSize.medium)
                Text(String(localized: "Lớn")).tag(Settings.ThumbSize.large)
            }
            LabeledContent(String(localized: "Độ rộng cột Gallery")) {
                HStack {
                    Slider(value: $settings.galleryColumnWidth, in: 120...480)
                    Text("\(Int(settings.galleryColumnWidth)) pt").monospacedDigit().frame(width: 56, alignment: .trailing)
                }
            }
        }
        .formStyle(.grouped)
    }

    private var controls: some View {
        Form {
            Picker(String(localized: "Lăn chuột thường"), selection: $settings.wheelAction) {
                Text(String(localized: "Zoom")).tag(Settings.WheelAction.zoom)
                Text(String(localized: "Chuyển ảnh")).tag(Settings.WheelAction.navigate)
            }
            Toggle(String(localized: "Đảo chiều vuốt chuyển ảnh"), isOn: $settings.invertSwipe)
            Picker(String(localized: "Bước zoom bằng phím"), selection: $settings.zoomStep) {
                ForEach([1.1, 1.25, 1.5, 2.0], id: \.self) { Text(String(format: "×%.2g", $0)).tag($0) }
            }
            Toggle(String(localized: "Giữ mức zoom khi chuyển ảnh"), isOn: $settings.keepZoom)
            Section {
                Text(String(localized: "Phím tắt: xem menu Trợ giúp → Phím tắt.")).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var performance: some View {
        Form {
            Picker(String(localized: "Số ảnh nạp trước mỗi phía"), selection: $settings.preloadEachSide) {
                ForEach(1...4, id: \.self) { Text("\($0)").tag($0) }
            }
            Picker(String(localized: "Bộ nhớ cho thumbnail"), selection: $settings.thumbnailMemoryMB) {
                Text("128 MB").tag(128)
                Text("256 MB").tag(256)
                Text(String(localized: "384 MB (≈ 9.000 ảnh)")).tag(384)
                Text("768 MB").tag(768)
            }
            Picker(String(localized: "Bộ nhớ cho ảnh lớn (tile)"), selection: $settings.tileMemoryMB) {
                ForEach([256, 512, 1024, 2048], id: \.self) { Text("\($0) MB").tag($0) }
            }
            Picker("RAW", selection: $settings.rawMode) {
                Text(String(localized: "Dùng ảnh xem trước nhúng")).tag(Settings.RawMode.embeddedPreview)
                Text(String(localized: "Luôn xử lý RAW đầy đủ")).tag(Settings.RawMode.fullRaw)
            }
            Section {
                Text(String(localized: "ViVuView không lưu thumbnail hay bộ nhớ đệm ra đĩa.")).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

/// Formats tab (docs/UI_SPEC.md §10.1).
struct FormatsTab: View {
    let associations: FileAssociations

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: "Mở bằng ViVuView khi double-click trong Finder:"))
                .font(.headline)
                .padding([.top, .horizontal])
            if !associations.canAssociate {
                Text(String(localized: "Hãy chuyển ViVuView vào thư mục Applications trước khi gắn định dạng."))
                    .foregroundStyle(.orange)
                    .padding(.horizontal)
            }
            List {
                ForEach(ImageFormat.Group.allCases, id: \.self) { group in
                    Section {
                        ForEach(associations.rows.filter { $0.format.group == group }) { row in
                            HStack {
                                Toggle(isOn: Binding(get: { row.ours }, set: { on in
                                    Task { await associations.set([row.format], on: on) }
                                })) {
                                    HStack(spacing: 6) {
                                        Text(row.format.name)
                                        Text(row.format.extensions.map { "." + $0 }.joined(separator: " "))
                                            .foregroundStyle(.secondary).font(.caption)
                                    }
                                }
                                Spacer()
                                Text(row.ours ? "ViVuView" : row.handlerName).foregroundStyle(.secondary).font(.caption)
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
                        }
                    }
                }
            }
            .disabled(!associations.canAssociate)
            HStack {
                Button(String(localized: "Chọn tất cả")) { Task { await associations.set(FormatCatalog.all, on: true) } }
                Button(String(localized: "Bỏ chọn tất cả")) { Task { await associations.set(FormatCatalog.all, on: false) } }
                Spacer()
            }
            .disabled(!associations.canAssociate)
            .padding(.horizontal)
            if !associations.message.isEmpty {
                Text(associations.message).foregroundStyle(.orange).padding(.horizontal)
            }
            Text(String(localized: "Bạn cũng có thể đổi trong Finder: chọn file → Get Info → Open with → Change All."))
                .font(.caption).foregroundStyle(.secondary)
                .padding([.horizontal, .bottom])
        }
    }

    private func title(_ group: ImageFormat.Group) -> String {
        switch group {
        case .common: String(localized: "Ảnh thông dụng")
        case .raw: String(localized: "RAW máy ảnh")
        case .special: String(localized: "Chuyên dụng")
        }
    }
}
