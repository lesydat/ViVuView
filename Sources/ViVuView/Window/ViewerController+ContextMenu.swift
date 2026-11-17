import AppKit
import UniformTypeIdentifiers
import ViVuCore

/// Right-click menu on the picture and on filmstrip thumbnails (docs/UI_SPEC.md §5, §7).
extension ViewerController {
    /// Shortcuts appear on the right of each item (`MenuCommand`); the menu itself is the system's (Liquid
    /// Glass on macOS 26+).
    func contextMenu() -> NSMenu? {
        guard !galleryOpen, let url = currentURL else { return nil }
        let menu = NSMenu()
        let openWith = NSMenuItem(title: String(localized: "Mở bằng"), action: nil, keyEquivalent: "")
        openWith.submenu = openWithMenu(for: url)
        menu.addItem(openWith)
        menu.addCommand(.revealInFinder, target: content)
        menu.addItem(NSSharingServicePicker(items: [url as NSURL]).standardShareMenuItem)
        menu.addItem(.separator())
        menu.addCommands([.copyImage, .copyPath], target: content)
        menu.addItem(.separator())
        menu.addCommands([.zoomIn, .zoomOut, .actualSize, .fit, .rotateLeft, .rotateRight], target: content)
        if meta?.isAnimated == true { menu.addCommand(.togglePlayback, target: content) }
        menu.addItem(.separator())
        menu.addCommand(.toggleInfo, target: content).state = infoOpen ? .on : .off
        menu.addCommand(.toggleFilmstrip, target: content).state = filmstripVisible ? .on : .off
        menu.addCommand(.toggleGallery, target: content)
        menu.addCommand(.toggleFullScreen, target: content).state = isFullScreen ? .on : .off
        if !isFullScreen { menu.addCommand(.followImageSize, target: content).state = fixedFrame ? .off : .on }
        menu.addItem(.separator())
        menu.addCommand(.moveToTrash, target: content)
        menu.addItem(.separator())
        menu.addCommand(.showShortcuts, target: content)
        return menu
    }

    /// Apps that open this kind of file, the system default first; from the type only (no file access here).
    private func openWithMenu(for url: URL) -> NSMenu {
        let menu = NSMenu()
        let type = UTType(filenameExtension: url.pathExtension) ?? .image
        let ours = Bundle.main.bundleURL.standardizedFileURL
        let preferred = NSWorkspace.shared.urlForApplication(toOpen: type)
        var apps = NSWorkspace.shared.urlsForApplications(toOpen: type).filter { $0.standardizedFileURL != ours }
        if let preferred, let i = apps.firstIndex(of: preferred) { apps.insert(apps.remove(at: i), at: 0) }
        for app in apps {
            let name = app.deletingPathExtension().lastPathComponent
            let title = app == preferred ? String(localized: "\(name) (mặc định)") : name
            let item = NSMenuItem(title: title, action: #selector(ViewerContentView.openWithApp(_:)), keyEquivalent: "")
            item.representedObject = app
            item.target = content
            menu.addItem(item)
            if app == preferred && apps.count > 1 { menu.addItem(.separator()) }
        }
        if !apps.isEmpty { menu.addItem(.separator()) }
        let other = NSMenuItem(title: String(localized: "Ứng dụng khác…"), action: #selector(ViewerContentView.openWithApp(_:)),
                               keyEquivalent: "")
        other.target = content
        menu.addItem(other)
        return menu
    }

    /// `app` nil asks the user to choose one.
    func openCurrent(with app: URL?) {
        guard let url = currentURL else { return }
        guard let app else {
            let panel = NSOpenPanel()
            panel.directoryURL = URL(fileURLWithPath: "/Applications")
            panel.allowedContentTypes = [.application]
            panel.prompt = String(localized: "Mở bằng")
            panel.beginSheetModal(for: window) { [weak self] response in
                MainActor.assumeIsolated {
                    guard response == .OK, let chosen = panel.url else { return }
                    self?.openCurrent(with: chosen)
                }
            }
            return
        }
        NSWorkspace.shared.open([url], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
    }
}
