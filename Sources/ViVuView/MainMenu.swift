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

        let viewMenu = ViewerMenu(title: String(localized: "Xem"))
        viewMenu.addCommands([.zoomIn, .zoomOut, .actualSize, .fit])
        viewMenu.addItem(.separator())
        viewMenu.addCommands([.rotateLeft, .rotateRight])
        viewMenu.addItem(.separator())
        viewMenu.addCommands([.toggleInfo, .toggleFilmstrip, .toggleGallery])
        viewMenu.addItem(.separator())
        viewMenu.addCommands([.toggleFullScreen])
        main.addItem(submenu: viewMenu, title: viewMenu.title)

        let goMenu = ViewerMenu(title: String(localized: "Đi tới"))
        goMenu.addCommands([.next, .previous, .first, .last])
        goMenu.addItem(.separator())
        goMenu.addCommands([.revealInFinder, .copyImage, .copyPath, .moveToTrash])
        main.addItem(submenu: goMenu, title: goMenu.title)

        let windowMenu = ViewerMenu(title: String(localized: "Cửa sổ"))
        windowMenu.addCommands([.followImageSize])
        windowMenu.addItem(withTitle: String(localized: "Thu nhỏ"),
                           action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        main.addItem(submenu: windowMenu, title: windowMenu.title)
        NSApplication.shared.windowsMenu = windowMenu

        let helpMenu = NSMenu(title: String(localized: "Trợ giúp"))
        helpMenu.addItem(withTitle: MenuCommand.of(.showShortcuts).title, action: #selector(AppDelegate.showShortcuts(_:)),
                         keyEquivalent: "/")
        main.addItem(submenu: helpMenu, title: helpMenu.title)
        NSApplication.shared.helpMenu = helpMenu

        return main
    }
}

/// One entry per command for the main menu and the right-click menu (docs/UI_SPEC.md §5, §6): the title, and
/// the shortcut shown on the right. Shortcuts without ⌘/⌃/⌥ (`[`, `T`, Home…) are only shown: the key itself
/// is handled by KeyBindings (see `ViewerMenu`).
struct MenuCommand {
    let title: String
    let key: String
    let modifiers: NSEvent.ModifierFlags

    @MainActor
    static func of(_ command: Command) -> MenuCommand {
        func key(_ scalar: Int) -> String { String(UnicodeScalar(UInt16(scalar))!) }
        switch command {
        case .zoomIn: return .init(title: String(localized: "Phóng to"), key: "+", modifiers: .command)
        case .zoomOut: return .init(title: String(localized: "Thu nhỏ"), key: "-", modifiers: .command)
        case .actualSize: return .init(title: String(localized: "Kích thước thật"), key: "0", modifiers: .command)
        case .fit: return .init(title: String(localized: "Vừa cửa sổ"), key: "9", modifiers: .command)
        case .rotateLeft: return .init(title: String(localized: "Xoay trái"), key: "[", modifiers: [])
        case .rotateRight: return .init(title: String(localized: "Xoay phải"), key: "]", modifiers: [])
        case .toggleInfo: return .init(title: String(localized: "Thông tin"), key: "i", modifiers: .command)
        case .toggleFilmstrip: return .init(title: "Filmstrip", key: "t", modifiers: [])
        case .toggleGallery: return .init(title: "Gallery", key: "g", modifiers: [])
        case .toggleFullScreen: return .init(title: String(localized: "Toàn màn hình"), key: "f", modifiers: [.command, .control])
        case .next: return .init(title: String(localized: "Ảnh sau"), key: key(NSRightArrowFunctionKey), modifiers: .command)
        case .previous: return .init(title: String(localized: "Ảnh trước"), key: key(NSLeftArrowFunctionKey), modifiers: .command)
        case .first: return .init(title: String(localized: "Ảnh đầu"), key: key(NSHomeFunctionKey), modifiers: [])
        case .last: return .init(title: String(localized: "Ảnh cuối"), key: key(NSEndFunctionKey), modifiers: [])
        case .revealInFinder: return .init(title: String(localized: "Hiện trong Finder"), key: "r", modifiers: [.command, .shift])
        case .copyImage: return .init(title: String(localized: "Copy ảnh"), key: "c", modifiers: .command)
        case .copyPath: return .init(title: String(localized: "Copy đường dẫn"), key: "c", modifiers: [.command, .shift])
        case .moveToTrash: return .init(title: String(localized: "Chuyển vào Thùng rác"), key: key(NSBackspaceCharacter), modifiers: .command)
        case .followImageSize: return .init(title: String(localized: "Theo kích thước ảnh"), key: "", modifiers: [])
        case .togglePlayback: return .init(title: String(localized: "Phát / tạm dừng"), key: " ", modifiers: [])
        case .previousFrame: return .init(title: String(localized: "Khung trước"), key: ",", modifiers: [])
        case .nextFrame: return .init(title: String(localized: "Khung sau"), key: ".", modifiers: [])
        case .toggleStretch: return .init(title: String(localized: "Kéo giãn tương phản"), key: "e", modifiers: [])
        case .showShortcuts: return .init(title: String(localized: "Phím tắt"), key: "/", modifiers: .command)
        case .escape: return .init(title: String(localized: "Đóng panel, Gallery, fullscreen, cửa sổ"), key: "", modifiers: [])
        case .panLeft, .panRight, .panUp, .panDown:
            return .init(title: String(localized: "Di chuyển ảnh"), key: "", modifiers: [])
        }
    }
}

/// Main-menu submenu whose plain-key shortcuts are display only, so `T`, `[`, Home… keep reaching the viewer
/// (and the gallery's type-to-select) through KeyBindings instead of being taken by the menu.
final class ViewerMenu: NSMenu {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.intersection([.command, .control, .option]).isEmpty { return false }
        return super.performKeyEquivalent(with: event)
    }
}

@MainActor
extension NSMenu {
    @discardableResult
    func addCommand(_ command: Command, target: AnyObject? = nil) -> NSMenuItem {
        let entry = MenuCommand.of(command)
        let item = NSMenuItem(title: entry.title, action: #selector(ViewerContentView.performMenuCommand(_:)),
                              keyEquivalent: entry.key)
        item.keyEquivalentModifierMask = entry.modifiers
        item.representedObject = command.rawValue
        item.target = target
        addItem(item)
        return item
    }

    func addCommands(_ commands: [Command], target: AnyObject? = nil) {
        for command in commands { addCommand(command, target: target) }
    }
}

private extension NSMenu {
    func addItem(submenu: NSMenu, title: String) {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.submenu = submenu
        addItem(item)
    }
}
