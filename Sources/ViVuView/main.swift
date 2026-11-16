import AppKit

// Entry point: no storyboard or xib (docs/TECH_SPEC.md §1).
MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate(arguments: CommandLine.arguments)
    app.delegate = delegate
    app.setActivationPolicy(.regular)
    app.mainMenu = MainMenu.make()
    app.run()
}
