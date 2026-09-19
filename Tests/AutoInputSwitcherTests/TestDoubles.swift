import Foundation

import AutoInputSwitcherCore

@testable import AutoInputSwitcherApp

// MARK: - Rule store

/// In-memory rule store with injectable load and save failures.
final class FakeRuleStore: RuleStore, @unchecked Sendable {
    struct Failure: Error, LocalizedError {
        let message: String

        var errorDescription: String? { message }
    }

    let url: URL

    private let lock = NSLock()
    private var storedRules: [AppRule]
    private var loadError: Error?
    private var saveError: Error?
    private var loadCountValue = 0
    private var saveCountValue = 0

    init(
        url: URL = URL(fileURLWithPath: "/tmp/AutoInputSwitcherTests/rules.json"),
        rules: [AppRule] = []
    ) {
        self.url = url
        self.storedRules = rules
    }

    var rules: [AppRule] {
        lock.lock()
        defer { lock.unlock() }
        return storedRules
    }

    var loadCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return loadCountValue
    }

    var saveCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return saveCountValue
    }

    func setRules(_ rules: [AppRule]) {
        lock.lock()
        defer { lock.unlock() }
        storedRules = rules
    }

    func failLoading(with error: Error?) {
        lock.lock()
        defer { lock.unlock() }
        loadError = error
    }

    func failSaving(with error: Error?) {
        lock.lock()
        defer { lock.unlock() }
        saveError = error
    }

    func load() throws -> [AppRule] {
        lock.lock()
        defer { lock.unlock() }

        loadCountValue += 1

        if let loadError {
            throw loadError
        }

        return storedRules
    }

    func save(_ rules: [AppRule]) throws {
        lock.lock()
        defer { lock.unlock() }

        saveCountValue += 1

        if let saveError {
            throw saveError
        }

        storedRules = rules
    }
}

// MARK: - Input sources

@MainActor
final class FakeInputSourceManager: InputSourceManaging {
    var sources: [InputSource]
    var current: InputSource?
    /// Result returned by selectInputSource, so a failing switch can be injected.
    var selectionResult = true

    private(set) var invalidateCacheCount = 0
    private(set) var selectRequestCount = 0
    private(set) var startMonitoringCount = 0
    private(set) var stopMonitoringCount = 0

    init(sources: [InputSource], current: InputSource? = nil) {
        self.sources = sources
        self.current = current
    }

    func availableInputSources() -> [InputSource] {
        sources
    }

    func invalidateCache() {
        invalidateCacheCount += 1
    }

    func currentInputSource() -> InputSource? {
        current
    }

    func selectInputSource(id: String) -> Bool {
        selectRequestCount += 1

        guard selectionResult else {
            return false
        }

        if let source = sources.first(where: { $0.id == id }) {
            current = source
        }

        return true
    }

    func startMonitoringEnabledSources(_ handler: @escaping @MainActor () -> Void) {
        startMonitoringCount += 1
    }

    func stopMonitoringEnabledSources() {
        stopMonitoringCount += 1
    }
}

// MARK: - Application scanning

/// Scanner stub. scan() sleeps for the injected delay so overlapping refreshes
/// and cancellation can be driven deterministically from tests.
final class FakeApplicationScanner: ApplicationScanning, @unchecked Sendable {
    private let lock = NSLock()
    private var storedResult: ApplicationScanResult
    private var scanCountValue = 0
    private let delay: TimeInterval

    init(result: ApplicationScanResult = .empty, delay: TimeInterval = 0) {
        self.storedResult = result
        self.delay = delay
    }

    var scanCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return scanCountValue
    }

    func setResult(_ result: ApplicationScanResult) {
        lock.lock()
        defer { lock.unlock() }
        storedResult = result
    }

    func scan() -> ApplicationScanResult {
        lock.lock()
        scanCountValue += 1
        let result = storedResult
        lock.unlock()

        if delay > 0 {
            Thread.sleep(forTimeInterval: delay)
        }

        return result
    }
}

// MARK: - Login items

@MainActor
final class FakeLoginItemManager: LoginItemManaging {
    var status: LaunchAtLoginStatus = .notRegistered
    var registerError: Error?
    var unregisterError: Error?

    private(set) var registerCount = 0
    private(set) var unregisterCount = 0
    private(set) var openSystemSettingsCount = 0

    func register() throws {
        registerCount += 1

        if let registerError {
            throw registerError
        }

        status = .enabled
    }

    func unregister() throws {
        unregisterCount += 1

        if let unregisterError {
            throw unregisterError
        }

        status = .notRegistered
    }

    func openSystemSettingsLoginItems() {
        openSystemSettingsCount += 1
    }
}

