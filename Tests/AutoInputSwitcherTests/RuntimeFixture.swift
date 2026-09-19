import Foundation
import XCTest

import AutoInputSwitcherCore

@testable import AutoInputSwitcherApp

enum TestInputSources {
    static let us = InputSource(id: "com.apple.keylayout.US", name: "U.S.")
    static let abc = InputSource(id: "com.apple.keylayout.ABC", name: "ABC")

    static let all = [us, abc]
}

/// Everything a test needs to drive an AppRuntime without touching the real user
/// configuration, input sources or login items.
@MainActor
struct RuntimeFixture {
    let runtime: AppRuntime
    let store: FakeRuleStore
    let inputSources: FakeInputSourceManager
    let scanner: FakeApplicationScanner
    let loginItems: FakeLoginItemManager
    let defaults: UserDefaults
    let suiteName: String
}

@MainActor
func makeFixture(
    rules: [AppRule] = [],
    installedApplications: [InstalledApplication] = [],
    sources: [InputSource] = TestInputSources.all,
    current: InputSource? = TestInputSources.us,
    scanDelay: TimeInterval = 0,
    scanRootCount: Int = 1
) -> RuntimeFixture {
    let suiteName = "AutoInputSwitcherTests." + UUID().uuidString
    let defaults = UserDefaults(suiteName: suiteName) ?? .standard
    defaults.removePersistentDomain(forName: suiteName)

    let store = FakeRuleStore(rules: rules)
    let inputSources = FakeInputSourceManager(sources: sources, current: current)
    let scanner = FakeApplicationScanner(
        result: ApplicationScanResult(
            applications: installedApplications,
            failedRoots: [],
            rootCount: scanRootCount
        ),
        delay: scanDelay
    )
    let loginItems = FakeLoginItemManager()

    let runtime = AppRuntime(
        store: store,
        inputSourceManager: inputSources,
        applicationScanner: scanner,
        loginItemManager: loginItems,
        switchCounter: SwitchCounter(defaults: defaults),
        defaults: defaults,
        updateController: nil,
        ownBundleIdentifier: "com.local.AutoInputSwitcher"
    )

    runtime.reloadInputSources()
    runtime.reloadRulesFromDisk()

    return RuntimeFixture(
        runtime: runtime,
        store: store,
        inputSources: inputSources,
        scanner: scanner,
        loginItems: loginItems,
        defaults: defaults,
        suiteName: suiteName
    )
}

func makeRule(
    bundleIdentifier: String,
    applicationName: String = "Terminal",
    inputSourceID: String = "com.apple.keylayout.US",
    inputSourceName: String = "U.S."
) -> AppRule {
    AppRule(
        bundleIdentifier: bundleIdentifier,
        applicationName: applicationName,
        inputSourceID: inputSourceID,
        inputSourceName: inputSourceName
    )
}

/// An application as the scanner would report it: present on disk.
func makeInstalledApplication(_ name: String, _ bundleIdentifier: String) -> InstalledApplication {
    InstalledApplication(
        name: name,
        bundleIdentifier: bundleIdentifier,
        url: URL(fileURLWithPath: "/Applications/" + name + ".app", isDirectory: true)
    )
}

@MainActor
func waitUntil(
    timeout: TimeInterval = 5,
    _ condition: () -> Bool
) async {
    let deadline = Date().addingTimeInterval(timeout)

    while Date() < deadline {
        if condition() {
            return
        }

        try? await Task.sleep(for: .milliseconds(10))
    }
}

