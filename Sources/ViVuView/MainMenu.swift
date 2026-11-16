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

        let windowMenu = NSMenu(title: String(localized: "Cửa sổ"))
        windowMenu.addItem(withTitle: String(localized: "Thu nhỏ"),
                           action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        main.addItem(submenu: windowMenu, title: windowMenu.title)
        NSApplication.shared.windowsMenu = windowMenu

        return main
    }
}

private extension NSMenu {
    func addItem(submenu: NSMenu, title: String) {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.submenu = submenu
        addItem(item)
    }
}
