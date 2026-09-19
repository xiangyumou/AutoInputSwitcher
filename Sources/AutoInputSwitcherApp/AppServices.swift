import Foundation

/// Keyboard input sources. Main-actor isolated because the underlying Carbon
/// APIs are only safe to call from the main thread.
@MainActor
protocol InputSourceManaging: AnyObject {
    func availableInputSources() -> [InputSource]
    func invalidateCache()
    func currentInputSource() -> InputSource?
    func selectInputSource(id: String) -> Bool
    func startMonitoringEnabledSources(_ handler: @escaping @MainActor () -> Void)
    func stopMonitoringEnabledSources()
}

@MainActor
protocol LoginItemManaging: AnyObject {
    var status: LaunchAtLoginStatus { get }
    func register() throws
    func unregister() throws
    func openSystemSettingsLoginItems()
}

/// File system scan for installed applications. Runs off the main actor, so the
/// result type and conformers must be sendable.
protocol ApplicationScanning: Sendable {
    func scan() -> ApplicationScanResult
}
