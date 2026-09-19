import AppKit
import AutoInputSwitcherCore
import Foundation

@MainActor
final class AppRuntime: ObservableObject {
    static let showMenuBarIconKey = "showMenuBarIcon"

    static var noSwitchInputSourceID: String {
        RuleSet.noSwitchInputSourceID
    }

    @Published private(set) var currentApplication: RunningApplicationInfo?
    @Published private(set) var currentInputSource: InputSource?
    @Published private(set) var installedApplications: [InstalledApplication] = []
    @Published private(set) var inputSources: [InputSource] = []
    @Published private(set) var ruleSet = RuleSet()
    @Published private(set) var switchCount = 0
    @Published private(set) var launchAtLoginStatus: LaunchAtLoginStatus = .notRegistered
    @Published private(set) var isScanning = false
    @Published private(set) var ruleEditingEnabled = true
    @Published private(set) var iconCacheGeneration = 0

    @Published private(set) var storageStatus: StatusMessage?
    @Published private(set) var scanStatus: StatusMessage?
    @Published private(set) var inputSourceStatus: StatusMessage?
    @Published private(set) var loginStatus: StatusMessage?

    @Published var searchText = ""
    @Published var applicationListScope: ApplicationListScope = .all
    @Published var showMenuBarIcon: Bool {
        didSet {
            guard showMenuBarIcon != oldValue else { return }
            defaults.set(showMenuBarIcon, forKey: Self.showMenuBarIconKey)
        }
    }

    private let store: any RuleStore
    private let inputSourceManager: any InputSourceManaging
    private let applicationScanner: any ApplicationScanning
    private let loginItemManager: any LoginItemManaging
    private let switchCounter: SwitchCounter
    private let defaults: UserDefaults
    private let ownBundleIdentifier: String?
    let updateController: UpdateController?

    private var scanTask: Task<Void, Never>?
    private var activationObserver: NSObjectProtocol?
    private var hasStarted = false
    private var hasStopped = false

    init(
        store: any RuleStore = JSONRuleStore.applicationSupportStore(),
        inputSourceManager: any InputSourceManaging = SystemInputSourceManager(),
        applicationScanner: any ApplicationScanning = InstalledApplicationScanner(),
        loginItemManager: any LoginItemManaging = SystemLoginItemManager(),
        switchCounter: SwitchCounter = SwitchCounter(),
        defaults: UserDefaults = .standard,
        updateController: UpdateController? = nil,
        ownBundleIdentifier: String? = Bundle.main.bundleIdentifier
    ) {
        self.store = store
        self.inputSourceManager = inputSourceManager
        self.applicationScanner = applicationScanner
        self.loginItemManager = loginItemManager
        self.switchCounter = switchCounter
        self.defaults = defaults
        self.updateController = updateController
        self.ownBundleIdentifier = ownBundleIdentifier
        self.showMenuBarIcon = defaults.object(forKey: Self.showMenuBarIconKey) as? Bool ?? true
        self.switchCount = switchCounter.count
        self.launchAtLoginStatus = loginItemManager.status
    }

    // MARK: - Lifecycle

    func start() {
        guard !hasStarted else { return }
        hasStarted = true

        loadRulesAtStartup()
        refreshInputSources()
        reportLoginStatus()
        startMonitoring()
        updateController?.start()
        refreshApplications()
        updateCurrentApplication(from: NSWorkspace.shared.frontmostApplication)
    }

    func stop() {
        guard !hasStopped else { return }
        hasStopped = true

        scanTask?.cancel()
        scanTask = nil
        isScanning = false

        if let activationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(activationObserver)
            self.activationObserver = nil
        }

        inputSourceManager.stopMonitoringEnabledSources()
        updateController?.stop()
    }

    // MARK: - Rules

    /// True when the rule file exists but could not be read, so editing is paused
    /// and the original file is left untouched.
    var hasStorageFailure: Bool {
        !ruleEditingEnabled
    }

    func reloadRulesFromDisk() {
        loadRulesFromDisk(reportingSuccess: true)
    }

    /// Loads the rules the way a cold start does: silently, so the status line
    /// keeps showing the application count instead of a confirmation message.
    func loadRulesAtStartup() {
        loadRulesFromDisk(reportingSuccess: false)
    }

    private func loadRulesFromDisk(reportingSuccess: Bool) {
        do {
            let loaded = try store.load()
            ruleSet = RuleSet(normalizing: loaded)
            ruleEditingEnabled = true
            storageStatus = reportingSuccess ? .rulesReloaded : nil
        } catch {
            // Keep whatever is already in memory; never write back over a file we
            // could not read.
            ruleEditingEnabled = false
            storageStatus = .rulesReadFailure
        }
    }

    func revealRulesFileInFinder() {
        let url = store.url
        let fileManager = FileManager.default

        if fileManager.fileExists(atPath: url.path) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
            return
        }

        let directory = url.deletingLastPathComponent()
        if fileManager.fileExists(atPath: directory.path) {
            NSWorkspace.shared.activateFileViewerSelecting([directory])
        }
    }

    // MARK: - Applications

    var configuredRuleCount: Int {
        ruleSet.rules.count
    }

    /// Installed applications plus applications that only exist as saved rules,
    /// so leftover rules stay visible and can still be edited or deleted.
    var displayApplications: [InstalledApplication] {
        var seenBundleIdentifiers: Set<String> = []
        var result: [InstalledApplication] = []

        for application in installedApplications
        where seenBundleIdentifiers.insert(application.bundleIdentifier).inserted {
            result.append(application)
        }

        for rule in ruleSet.rules
        where seenBundleIdentifiers.insert(rule.bundleIdentifier).inserted {
            let name = rule.applicationName.trimmingCharacters(in: .whitespacesAndNewlines)
            result.append(
                InstalledApplication(
                    name: name.isEmpty ? rule.bundleIdentifier : name,
                    bundleIdentifier: rule.bundleIdentifier,
                    url: nil
                )
            )
        }

        return result.sorted { lhs, rhs in
            let comparison = lhs.name.localizedCaseInsensitiveCompare(rhs.name)
            if comparison == .orderedSame {
                return lhs.bundleIdentifier < rhs.bundleIdentifier
            }
            return comparison == .orderedAscending
        }
    }

    var filteredInstalledApplications: [InstalledApplication] {
        let filter = ApplicationListFilter(
            query: searchText,
            scope: applicationListScope,
            configuredBundleIdentifiers: Set(ruleSet.rules.map(\.bundleIdentifier))
        )

        return displayApplications.filter {
            filter.includes(
                ApplicationListEntry(
                    displayName: $0.name,
                    bundleIdentifier: $0.bundleIdentifier,
                    isInstalled: $0.isInstalled
                )
            )
        }
    }

    /// Only one scan may be in flight at a time, and the previous list stays on
    /// screen until a usable result arrives.
    func refreshApplications() {
        guard !isScanning else { return }

        isScanning = true
        let scanner = applicationScanner

        scanTask = Task { [weak self] in
            let result = await Task.detached(priority: .userInitiated) {
                scanner.scan()
            }.value

            guard let self, !Task.isCancelled else { return }
            self.finishScan(with: result)
        }
    }

    private func finishScan(with result: ApplicationScanResult) {
        scanTask = nil
        isScanning = false

        if result.isTotalFailure {
            // Nothing usable came back: keep the list that is already on screen.
            scanStatus = StatusMessage(
                text: "应用扫描失败，已保留原有列表。",
                severity: .error
            )
            return
        }

        if result.isPartialFailure {
            if !result.applications.isEmpty {
                installedApplications = result.applications
                iconCacheGeneration += 1
            }

            scanStatus = StatusMessage(
                text: "部分目录扫描失败：" + result.failedRoots.map(\.path).joined(separator: "、"),
                severity: .warning
            )
            return
        }

        installedApplications = result.applications
        iconCacheGeneration += 1
        scanStatus = nil
    }

    // MARK: - Input sources

    func reloadInputSources() {
        refreshInputSources()
    }

    private func refreshInputSources() {
        inputSourceManager.invalidateCache()
        inputSources = inputSourceManager.availableInputSources()
        currentInputSource = inputSourceManager.currentInputSource()
    }

    func selectedInputSourceID(for application: InstalledApplication) -> String {
        ruleSet.rule(forBundleIdentifier: application.bundleIdentifier)?.inputSourceID
            ?? Self.noSwitchInputSourceID
    }

    /// Picker entries for one application, including the saved input source when
    /// it is no longer installed, so a rule is never silently rewritten.
    func inputSourceChoices(for application: InstalledApplication) -> [InputSourceChoice] {
        var choices = inputSources.map { InputSourceChoice(id: $0.id, name: $0.name) }
        let selectedID = selectedInputSourceID(for: application)

        if
            selectedID != Self.noSwitchInputSourceID,
            !choices.contains(where: { $0.id == selectedID })
        {
            let savedName = ruleSet
                .rule(forBundleIdentifier: application.bundleIdentifier)?
                .inputSourceName
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let displayName = (savedName?.isEmpty == false) ? savedName! : selectedID

            choices.append(
                InputSourceChoice(id: selectedID, name: "不可用：" + displayName)
            )
        }

        return choices
    }

    /// Candidate first, disk second, published state last: a failed save leaves
    /// both the visible state and the file untouched.
    func setInputSourceID(_ inputSourceID: String, for application: InstalledApplication) {
        guard ruleEditingEnabled else {
            storageStatus = .rulesReadFailure
            return
        }

        var candidate = ruleSet

        if inputSourceID == Self.noSwitchInputSourceID {
            candidate.remove(bundleIdentifier: application.bundleIdentifier)
        } else if let inputSource = inputSources.first(where: { $0.id == inputSourceID }) {
            candidate.upsert(
                AppRule(
                    bundleIdentifier: application.bundleIdentifier,
                    applicationName: application.name,
                    inputSourceID: inputSource.id,
                    inputSourceName: inputSource.name
                )
            )
        } else if
            ruleSet.rule(forBundleIdentifier: application.bundleIdentifier)?.inputSourceID
                == inputSourceID
        {
            // Re-selecting the input source that is already saved, but currently
            // unavailable, keeps the existing rule.
            return
        } else {
            inputSourceStatus = StatusMessage(
                text: "所选输入法当前不可用，规则未修改。",
                severity: .warning
            )
            return
        }

        guard candidate != ruleSet else { return }

        do {
            try store.save(candidate.rules)
            ruleSet = candidate
            storageStatus = .rulesSaved
        } catch {
            storageStatus = .rulesSaveFailure
        }
    }

    // MARK: - Launch at login

    var isLaunchAtLoginEnabled: Bool {
        launchAtLoginStatus.isEnabled
    }

    func setLaunchAtLoginEnabled(_ enabled: Bool) {
        do {
            if enabled {
                if loginItemManager.status == .requiresApproval {
                    // Never register again while the system is waiting for the
                    // user to allow the login item.
                    loginStatus = StatusMessage(
                        text: "开机自启正在等待系统批准，请在“系统设置 › 通用 › 登录项”中允许。",
                        severity: .warning
                    )
                    refreshLaunchAtLoginStatus()
                } else if loginItemManager.status != .enabled {
                    try loginItemManager.register()
                    reportLoginStatus()
                }
            } else {
                if loginItemManager.status.isRegistered {
                    try loginItemManager.unregister()
                }
                reportLoginStatus()
            }
        } catch {
            refreshLaunchAtLoginStatus()
            loginStatus = StatusMessage(
                text: "开机自启设置失败：" + error.localizedDescription,
                severity: .error
            )
        }
    }

    func refreshLaunchAtLoginStatus() {
        launchAtLoginStatus = loginItemManager.status
    }

    func openLoginItemsSystemSettings() {
        loginItemManager.openSystemSettingsLoginItems()
    }

    private func reportLoginStatus() {
        refreshLaunchAtLoginStatus()

        switch launchAtLoginStatus {
        case .enabled:
            loginStatus = StatusMessage(text: "已开启开机自启")
        case .notRegistered:
            loginStatus = StatusMessage(text: "已关闭开机自启")
        case .requiresApproval:
            loginStatus = StatusMessage(
                text: "开机自启正在等待系统批准，请在“系统设置 › 通用 › 登录项”中允许。",
                severity: .warning
            )
        case .notFound:
            loginStatus = StatusMessage(
                text: "系统未找到登录项注册信息，请尝试重新开启开机自启。",
                severity: .warning
            )
        }
    }

    // MARK: - Updates

    var canCheckForUpdates: Bool {
        updateController?.canCheckForUpdates ?? false
    }

    func checkForUpdates() {
        updateController?.checkForUpdates()
    }

    // MARK: - Status line

    /// The most severe outstanding status. Unrelated activity can only ever clear
    /// its own entry, so an error is never hidden by a later informational message.
    var primaryStatus: StatusMessage? {
        let candidates = [storageStatus, scanStatus, inputSourceStatus, loginStatus]
            .compactMap { $0 }

        var best: StatusMessage?
        for candidate in candidates {
            if let current = best {
                if candidate.severity > current.severity {
                    best = candidate
                }
            } else {
                best = candidate
            }
        }

        return best
    }

    var statusText: String {
        primaryStatus?.text ?? "显示 " + String(filteredInstalledApplications.count) + " 个应用"
    }

    // MARK: - Foreground application monitoring

    private func startMonitoring() {
        guard activationObserver == nil else { return }

        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard
                let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
                    as? NSRunningApplication
            else {
                return
            }

            let activatedProcessIdentifier = app.processIdentifier
            let runtime = self

            Task { @MainActor in
                // Re-check just before acting: the foreground application may have
                // changed again while this event was queued.
                guard
                    let runtime,
                    let frontmost = NSWorkspace.shared.frontmostApplication,
                    frontmost.processIdentifier == activatedProcessIdentifier
                else {
                    return
                }

                runtime.updateCurrentApplication(from: frontmost)
            }
        }

        inputSourceManager.startMonitoringEnabledSources { [weak self] in
            self?.refreshInputSources()
        }
    }

    private func updateCurrentApplication(from app: NSRunningApplication?) {
        guard
            let app,
            let bundleIdentifier = app.bundleIdentifier,
            bundleIdentifier != ownBundleIdentifier
        else {
            currentApplication = nil
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
            inputSourceStatus = nil
            return
        }

        if inputSourceManager.currentInputSource()?.id != rule.inputSourceID {
            // The count only tracks input sources that were actually switched.
            if inputSourceManager.selectInputSource(id: rule.inputSourceID) {
                switchCounter.recordSwitch()
                switchCount = switchCounter.count
                inputSourceStatus = nil
            } else {
                inputSourceStatus = StatusMessage(
                    text: "输入法切换失败：" + rule.inputSourceName + " 当前不可用。",
                    severity: .warning
                )
            }
        } else {
            inputSourceStatus = nil
        }

        currentInputSource = inputSourceManager.currentInputSource()
    }
}
