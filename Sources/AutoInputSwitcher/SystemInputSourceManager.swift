import Carbon
import Foundation

final class SystemInputSourceManager {
    func availableInputSources() -> [InputSource] {
        let filters: [String: Any] = [
            kTISPropertyInputSourceCategory as String: kTISCategoryKeyboardInputSource as String,
            kTISPropertyInputSourceIsSelectCapable as String: true
        ]

        let list = TISCreateInputSourceList(filters as CFDictionary, false).takeRetainedValue()
        return (list as NSArray)
            .map { $0 as! TISInputSource }
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

    private func inputSource(matching id: String) -> TISInputSource? {
        let filters: [String: Any] = [
            kTISPropertyInputSourceID as String: id
        ]
        let list = TISCreateInputSourceList(filters as CFDictionary, false).takeRetainedValue()
        return (list as NSArray).map { $0 as! TISInputSource }.first
    }

    private func stringProperty(_ source: TISInputSource, _ key: CFString) -> String? {
        guard let rawValue = TISGetInputSourceProperty(source, key) else {
            return nil
        }

        return Unmanaged<CFString>
            .fromOpaque(rawValue)
            .takeUnretainedValue() as String
    }
}
