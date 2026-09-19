import Carbon
import Foundation

@MainActor
final class SystemInputSourceManager: NSObject, InputSourceManaging {
    /// Same value as kTISNotifyEnabledKeyboardInputSourcesChanged. The literal is
    /// used so the behaviour does not depend on a Carbon constant being visible.
    private static let enabledInputSourcesChanged = Notification.Name(
        "AppleEnabledInputSourcesChangedNotification"
    )

    /// Safety net for changes that never arrive as a distributed notification.
    private static let cacheLifetime: TimeInterval = 3

    private var cachedInputSources: [InputSource]?
    private var cacheDate: Date?
    private var changeHandler: (@MainActor () -> Void)?

    func availableInputSources() -> [InputSource] {
        if
            let cached = cachedInputSources,
            let cacheDate,
            Date().timeIntervalSince(cacheDate) < Self.cacheLifetime
        {
            return cached
        }

        let sources = computeAvailableInputSources()
        cachedInputSources = sources
        cacheDate = Date()
        return sources
    }

    func invalidateCache() {
        cachedInputSources = nil
        cacheDate = nil
    }

    func startMonitoringEnabledSources(_ handler: @escaping @MainActor () -> Void) {
        changeHandler = handler

        guard observers.isEmpty else { return }

        let center = DistributedNotificationCenter.default()
        observers.append(
            center.addObserver(
                self,
                selector: #selector(handleEnabledInputSourcesChanged),
                name: Self.enabledInputSourcesChanged,
                object: nil
            )
        )
    }

    func stopMonitoringEnabledSources() {
        changeHandler = nil
        let center = DistributedNotificationCenter.default()
        for observer in observers {
            center.removeObserver(observer)
        }
        observers.removeAll()
    }

    @objc private func handleEnabledInputSourcesChanged() {
        invalidateCache()
        changeHandler?()
    }

    func currentInputSource() -> InputSource? {
        let source = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
        guard
            let id = stringProperty(source, kTISPropertyInputSourceID),
            let name = stringProperty(source, kTISPropertyLocalizedName)
        else {
            return nil
        }

        return InputSource(id: id, name: name)
    }

    func selectInputSource(id: String) -> Bool {
        guard let source = inputSource(matching: id) else {
            return false
        }

        return TISSelectInputSource(source) == noErr
    }

    private func computeAvailableInputSources() -> [InputSource] {
        let filters: [String: Any] = [
            kTISPropertyInputSourceCategory as String: kTISCategoryKeyboardInputSource as String,
            kTISPropertyInputSourceIsSelectCapable as String: true
        ]

        let list = TISCreateInputSourceList(filters as CFDictionary, false).takeRetainedValue()
        return (list as NSArray)
            .compactMap { $0 as? TISInputSource }
            .compactMap { source in
                guard
                    let id = stringProperty(source, kTISPropertyInputSourceID),
                    let name = stringProperty(source, kTISPropertyLocalizedName)
                else {
                    return nil
                }

                return InputSource(id: id, name: name)
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func inputSource(matching id: String) -> TISInputSource? {
        let filters: [String: Any] = [
            kTISPropertyInputSourceID as String: id
        ]
        let list = TISCreateInputSourceList(filters as CFDictionary, false).takeRetainedValue()
        return (list as NSArray).compactMap { $0 as? TISInputSource }.first
    }

    private func stringProperty(_ source: TISInputSource, _ key: CFString) -> String? {
        guard let rawValue = TISGetInputSourceProperty(source, key) else {
            return nil
        }

        return Unmanaged<CFString>
            .fromOpaque(rawValue)
            .takeUnretainedValue() as String
    }

    private var observers: [NSObjectProtocol] = []
}
