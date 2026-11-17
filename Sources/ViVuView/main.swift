import AppKit

// Entry point: no storyboard or xib (docs/TECH_SPEC.md §1).
import QuartzCore

/// Process start in CACurrentMediaTime units, for --bench-open.
let launchUptime = CACurrentMediaTime()
// Line-buffered output so script and bench results appear immediately when redirected.
setvbuf(stdout, nil, _IOLBF, 0)
SVGRasterizer.install()

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate(arguments: CommandLine.arguments)
    app.delegate = delegate
    app.setActivationPolicy(.regular)
    app.mainMenu = MainMenu.make()
    app.run()
}
