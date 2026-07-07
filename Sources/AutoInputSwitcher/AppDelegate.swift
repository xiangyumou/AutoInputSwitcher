import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var runtime: AppRuntime?
    private var window: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        if activateExistingInstanceIfNeeded() {
            NSApp.terminate(nil)
            return
        }

        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(showWindowFromNotification),
            name: .autoInputSwitcherShowWindow,
            object: nil
        )

        runtime = AppRuntime()
        showWindow()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        showWindow()
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        DistributedNotificationCenter.default().removeObserver(self)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        true
    }

    func showWindow() {
        if window == nil {
            guard let runtime else {
                return
            }

            let contentView = MainWindowView(runtime: runtime) {
                NSApp.terminate(nil)
            }
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 980, height: 640),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.title = "AutoInputSwitcher"
            window.contentView = NSHostingView(rootView: contentView)
            window.center()
            window.delegate = self
            window.isReleasedWhenClosed = false
            self.window = window
        }

        if window?.isMiniaturized == true {
            window?.deminiaturize(nil)
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func activateExistingInstanceIfNeeded() -> Bool {
        guard let bundleIdentifier = Bundle.main.bundleIdentifier else {
            return false
        }

        let currentPID = ProcessInfo.processInfo.processIdentifier
        let existingInstances = NSRunningApplication
            .runningApplications(withBundleIdentifier: bundleIdentifier)
            .filter { $0.processIdentifier != currentPID && !$0.isTerminated }

        guard !existingInstances.isEmpty else {
            return false
        }

        DistributedNotificationCenter.default().post(
            name: .autoInputSwitcherShowWindow,
            object: bundleIdentifier
        )
        return true
    }

    @objc private func showWindowFromNotification() {
        showWindow()
    }
}

private extension Notification.Name {
    static let autoInputSwitcherShowWindow = Notification.Name(
        "com.local.AutoInputSwitcher.showWindow"
    )
}
