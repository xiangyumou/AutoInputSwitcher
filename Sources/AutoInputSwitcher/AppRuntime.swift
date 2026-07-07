import AppKit
import AutoInputSwitcherCore
import Foundation
import ServiceManagement

@MainActor
final class AppRuntime: ObservableObject {
    @Published private(set) var currentApplication: RunningApplicationInfo?
    @Published private(set) var currentInputSource: InputSource?
    @Published private(set) var installedApplications: [InstalledApplication]
    @Published private(set) var inputSources: [InputSource]
    @Published private(set) var ruleSet: RuleSet
    @Published private(set) var switchCount: Int
    @Published var launchAtLoginEnabled: Bool
    @Published var searchText: String
    @Published var applicationListScope: ApplicationListScope
    @Published var statusMessage: String

    private let store: JSONRuleStore
    private let inputSourceManager: SystemInputSourceManager
    private let applicationScanner: InstalledApplicationScanner
    private let switchCounter: SwitchCounter
    private let ownBundleIdentifier: String?
    private var activationObserver: NSObjectProtocol?

    init(
        store: JSONRuleStore = .applicationSupportStore(),
        inputSourceManager: SystemInputSourceManager = SystemInputSourceManager(),
        applicationScanner: InstalledApplicationScanner = InstalledApplicationScanner(),
        switchCounter: SwitchCounter = SwitchCounter()
    ) {
        self.store = store
        self.inputSourceManager = inputSourceManager
        self.applicationScanner = applicationScanner
        self.switchCounter = switchCounter
        self.ownBundleIdentifier = Bundle.main.bundleIdentifier
        let loadedInputSources = inputSourceManager.availableInputSources()
        let loadedCurrentInputSource = inputSourceManager.currentInputSource()
        self.installedApplications = applicationScanner.scan()
        self.inputSources = loadedInputSources
        self.currentInputSource = loadedCurrentInputSource
        self.switchCount = switchCounter.count
        self.launchAtLoginEnabled = SMAppService.mainApp.status == .enabled
        self.searchText = ""
        self.applicationListScope = .all
        self.statusMessage = ""

        do {
            self.ruleSet = RuleSet(rules: try store.load())
        } catch {
            self.ruleSet = RuleSet()
            self.statusMessage = "规则读取失败"
        }

        startMonitoring()
        updateCurrentApplication(from: NSWorkspace.shared.frontmostApplication)
    }

    var configuredRuleCount: Int {
        ruleSet.rules.count
    }

    var filteredInstalledApplications: [InstalledApplication] {
        let filter = ApplicationListFilter(
            query: searchText,
            scope: applicationListScope,
            configuredBundleIdentifiers: Set(ruleSet.rules.map(\.bundleIdentifier))
        )

        return installedApplications.filter {
            filter.includes(
                ApplicationListEntry(
                    displayName: $0.name,
                    bundleIdentifier: $0.bundleIdentifier
                )
            )
        }
    }

    func reloadInputSources() {
        inputSources = inputSourceManager.availableInputSources()
        currentInputSource = inputSourceManager.currentInputSource()
    }

    func reloadApplications() {
        installedApplications = applicationScanner.scan()
    }

    func selectedInputSourceID(for application: InstalledApplication) -> String {
        ruleSet.rule(forBundleIdentifier: application.bundleIdentifier)?.inputSourceID ?? Self.noSwitchInputSourceID
    }

    func setInputSourceID(_ inputSourceID: String, for application: InstalledApplication) {
        var updatedRuleSet = ruleSet

        if inputSourceID == Self.noSwitchInputSourceID {
            updatedRuleSet.remove(bundleIdentifier: application.bundleIdentifier)
        } else if let inputSource = inputSources.first(where: { $0.id == inputSourceID }) {
            updatedRuleSet.upsert(
                AppRule(
                    bundleIdentifier: application.bundleIdentifier,
                    applicationName: application.name,
                    inputSourceID: inputSource.id,
                    inputSourceName: inputSource.name
                )
            )
        }

        ruleSet = updatedRuleSet
        saveRules()
    }

    func setLaunchAtLoginEnabled(_ enabled: Bool) {
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            }

            launchAtLoginEnabled = SMAppService.mainApp.status == .enabled
            statusMessage = launchAtLoginEnabled ? "已开启开机自启" : "已关闭开机自启"
        } catch {
            launchAtLoginEnabled = SMAppService.mainApp.status == .enabled
            statusMessage = "开机自启设置失败"
        }
    }

    private func startMonitoring() {
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard
                let self,
                let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            else {
                return
            }

            Task { @MainActor in
                self.updateCurrentApplication(from: app)
            }
        }
    }

    private func updateCurrentApplication(from app: NSRunningApplication?) {
        guard
            let app,
            let bundleIdentifier = app.bundleIdentifier,
            bundleIdentifier != ownBundleIdentifier
        else {
            currentInputSource = inputSourceManager.currentInputSource()
            return
        }

        let applicationInfo = RunningApplicationInfo(
            bundleIdentifier: bundleIdentifier,
            name: app.localizedName ?? bundleIdentifier
        )
        currentApplication = applicationInfo
        applyRuleIfNeeded(for: applicationInfo)
    }

    private func applyRuleIfNeeded(for app: RunningApplicationInfo) {
        guard let rule = ruleSet.rule(forBundleIdentifier: app.bundleIdentifier) else {
            currentInputSource = inputSourceManager.currentInputSource()
            statusMessage = ""
            return
        }

        if inputSourceManager.currentInputSource()?.id != rule.inputSourceID {
            let switched = inputSourceManager.selectInputSource(id: rule.inputSourceID)
            if switched {
                switchCounter.recordSwitch()
                switchCount = switchCounter.count
            }
            statusMessage = switched ? "" : "输入法切换失败"
        }
        currentInputSource = inputSourceManager.currentInputSource()
    }

    private func saveRules() {
        do {
            try store.save(ruleSet.rules)
            statusMessage = "已保存"
        } catch {
            statusMessage = "规则保存失败"
        }
    }

    static let noSwitchInputSourceID = "-"
}
