import SwiftUI
import AppKit

// Agency OS - local control plane for MCP servers, skills, rules, and agent
// divisions across Claude Code, Claude Desktop, Codex, and Antigravity.
//
// Built as a Swift Package executable so it runs unsandboxed and can read the
// agent config files scattered across the home directory. Launch with:
//   cd internal/agency-os && swift run
// Entry point. `--self-test` runs the CLT test suite and exits before any window
// is created; otherwise the normal SwiftUI app launches.
@main
enum AppEntry {
    static func main() {
        if CommandLine.arguments.contains("--self-test") {
            SelfTest.runAndExit()
        }
        AgencyOSApp.main()
    }
}

struct AgencyOSApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup("Agency OS") {
            RootView()
                .frame(minWidth: 1120, minHeight: 720)
                .preferredColorScheme(.dark)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // A bare SPM executable defaults to a background accessory; promote it
        // to a regular app so the window and Dock icon appear.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
