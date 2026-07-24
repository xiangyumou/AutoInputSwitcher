import AppKit
import AutoInputSwitcherCore
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var runtime: AppRuntime?
    private var window: NSWindow?
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        UserDefaults.standard.register(defaults: ["showMenuBarIcon": true])

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

        runtime?.updateMenuBarIconVisibility = { [weak self] show in
            self?.updateMenuBarIconVisibility(show)
        }

        let rulesURL = JSONRuleStore.applicationSupportStore().url
        let isFirstLaunch = !FileManager.default.fileExists(atPath: rulesURL.path)
        if isFirstLaunch { showWindow() }

        setupMenuBar()
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

    private func setupMenuBar() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(systemSymbolName: "keyboard", accessibilityDescription: "AutoInputSwitcher")
        item.button?.action = #selector(toggleWindow)
        item.button?.target = self

        let menu = NSMenu()
        menu.addItem(withTitle: "显示窗口", action: #selector(showWindowFromMenu), keyEquivalent: "")
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "关于 AutoInputSwitcher", action: #selector(showAboutPanel), keyEquivalent: "")
        menu.addItem(withTitle: "退出", action: #selector(terminateApp), keyEquivalent: "q")
        item.menu = menu

        item.isVisible = UserDefaults.standard.bool(forKey: "showMenuBarIcon")
        statusItem = item
    }

    @objc private func toggleWindow() {
        guard let window else {
            showWindow()
            return
        }

        if window.isVisible && window.isKeyWindow {
            window.orderOut(nil)
        } else {
            showWindow()
        }
    }

    @objc private func showWindowFromMenu() {
        showWindow()
    }

    @objc private func showAboutPanel() {
        NSApp.orderFrontStandardAboutPanel(nil)
    }

    @objc private func terminateApp() {
        NSApp.terminate(nil)
    }

    func updateMenuBarIconVisibility(_ show: Bool) {
        UserDefaults.standard.set(show, forKey: "showMenuBarIcon")
        statusItem?.isVisible = show
    }
}

private extension Notification.Name {
    static let autoInputSwitcherShowWindow = Notification.Name(
        "com.local.AutoInputSwitcher.showWindow"
    )
}
