import AppKit

/// Main menu built in code. Every command also gets a menu item as its milestone lands
/// (docs/UI_SPEC.md §6: "mọi lệnh cũng có trong menu chính").
@MainActor
enum MainMenu {
    static func make() -> NSMenu {
        let main = NSMenu()

        let appMenu = NSMenu()
        appMenu.addItem(withTitle: String(localized: "Giới thiệu ViVuView"),
                        action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: String(localized: "Cài đặt…"), action: #selector(AppDelegate.showSettings(_:)), keyEquivalent: ",")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: String(localized: "Ẩn ViVuView"),
                        action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: String(localized: "Thoát ViVuView"),
                        action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        main.addItem(submenu: appMenu, title: "ViVuView")

        let fileMenu = NSMenu(title: String(localized: "Tệp"))
        fileMenu.addItem(withTitle: String(localized: "Mở…"), action: #selector(AppDelegate.openDocument(_:)), keyEquivalent: "o")
        let recent = NSMenuItem(title: String(localized: "Mở gần đây"), action: nil, keyEquivalent: "")
        let recentMenu = NSMenu(title: recent.title)
        recentMenu.addItem(withTitle: String(localized: "Xoá danh sách"),
                           action: #selector(NSDocumentController.clearRecentDocuments(_:)), keyEquivalent: "")
        recent.submenu = recentMenu
        fileMenu.addItem(recent)
        fileMenu.addItem(.separator())
        fileMenu.addItem(withTitle: String(localized: "Đóng"),
                         action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        main.addItem(submenu: fileMenu, title: fileMenu.title)

        let viewMenu = NSMenu(title: String(localized: "Xem"))
        viewMenu.addCommand(String(localized: "Phóng to"), .zoomIn, "+", [.command])
        viewMenu.addCommand(String(localized: "Thu nhỏ"), .zoomOut, "-", [.command])
        viewMenu.addCommand(String(localized: "Kích thước thật (0)"), .actualSize, "0", [.command])
        viewMenu.addCommand(String(localized: "Vừa cửa sổ (\\)"), .fit, "9", [.command])
        viewMenu.addItem(.separator())
        viewMenu.addCommand(String(localized: "Xoay trái ([)"), .rotateLeft, "", [])
        viewMenu.addCommand(String(localized: "Xoay phải (])"), .rotateRight, "", [])
        viewMenu.addItem(.separator())
        viewMenu.addCommand(String(localized: "Thông tin (I)"), .toggleInfo, "i", [.command])
        viewMenu.addCommand(String(localized: "Filmstrip (T)"), .toggleFilmstrip, "", [])
        viewMenu.addCommand(String(localized: "Gallery (G)"), .toggleGallery, "", [])
        viewMenu.addItem(.separator())
        viewMenu.addCommand(String(localized: "Toàn màn hình (F)"), .toggleFullScreen, "f", [.command, .control])
        main.addItem(submenu: viewMenu, title: viewMenu.title)

        let goMenu = NSMenu(title: String(localized: "Đi tới"))
        goMenu.addCommand(String(localized: "Ảnh sau"), .next, String(UnicodeScalar(NSRightArrowFunctionKey)!), [.command])
        goMenu.addCommand(String(localized: "Ảnh trước"), .previous, String(UnicodeScalar(NSLeftArrowFunctionKey)!), [.command])
        goMenu.addCommand(String(localized: "Ảnh đầu (Home)"), .first, "", [])
        goMenu.addCommand(String(localized: "Ảnh cuối (End)"), .last, "", [])
        goMenu.addItem(.separator())
        goMenu.addCommand(String(localized: "Hiện trong Finder"), .revealInFinder, "r", [.command, .shift])
        goMenu.addCommand(String(localized: "Copy ảnh"), .copyImage, "c", [.command])
        goMenu.addCommand(String(localized: "Copy đường dẫn"), .copyPath, "c", [.command, .shift])
        goMenu.addCommand(String(localized: "Chuyển vào Thùng rác"), .moveToTrash, String(UnicodeScalar(NSBackspaceCharacter)!), [.command])
        main.addItem(submenu: goMenu, title: goMenu.title)

        let windowMenu = NSMenu(title: String(localized: "Cửa sổ"))
        windowMenu.addCommand(String(localized: "Theo kích thước ảnh"), .followImageSize, "", [])
        windowMenu.addItem(withTitle: String(localized: "Thu nhỏ"),
                           action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        main.addItem(submenu: windowMenu, title: windowMenu.title)
        NSApplication.shared.windowsMenu = windowMenu

        let helpMenu = NSMenu(title: String(localized: "Trợ giúp"))
        helpMenu.addItem(withTitle: String(localized: "Phím tắt"), action: #selector(AppDelegate.showShortcuts(_:)), keyEquivalent: "/")
        main.addItem(submenu: helpMenu, title: helpMenu.title)
        NSApplication.shared.helpMenu = helpMenu

        return main
    }
}

extension MainMenu {
    /// The keyboard table of docs/UI_SPEC.md §6, shown from Help → Shortcuts.
    static var shortcutsText: String {
        [
            "← → · Space ⇧Space · PageUp PageDown: " + String(localized: "ảnh trước / sau (giữ để lướt)"),
            "Home / End: " + String(localized: "ảnh đầu / cuối"),
            "↑ ↓ · + −: " + String(localized: "zoom (đang zoom thì mũi tên pan; ⌘← ⌘→ chuyển ảnh)"),
            "0: 100%   \\: " + String(localized: "vừa cửa sổ (nhấn 2 lần: theo kích thước ảnh)"),
            "[ ]: " + String(localized: "xoay trái / phải"),
            "F: " + String(localized: "toàn màn hình") + "   T: Filmstrip   G / Enter: Gallery   I: " + String(localized: "thông tin"),
            "E: " + String(localized: "kéo giãn tương phản (ảnh 16-bit)") + "   , .: " + String(localized: "khung trước / sau (ảnh động)"),
            "⌘C · ⌘⇧C: " + String(localized: "copy ảnh · copy đường dẫn") + "   ⌘⇧R: " + String(localized: "hiện trong Finder"),
            "⌘⌫: " + String(localized: "chuyển vào Thùng rác") + "   Esc: " + String(localized: "đóng panel / gallery / fullscreen / cửa sổ"),
        ].joined(separator: "\n")
    }
}

private extension NSMenu {
    func addCommand(_ title: String, _ command: Command, _ key: String, _ modifiers: NSEvent.ModifierFlags) {
        let item = NSMenuItem(title: title, action: #selector(ViewerContentView.performMenuCommand(_:)), keyEquivalent: key)
        item.keyEquivalentModifierMask = modifiers
        item.representedObject = command.rawValue
        addItem(item)
    }

    func addItem(submenu: NSMenu, title: String) {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.submenu = submenu
        addItem(item)
    }
}
