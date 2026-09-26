import AppKit
import CoreGraphics
import Foundation
import os

enum VoiceLog {
    static let logger = Logger(subsystem: "com.local.AutoInputSwitcher", category: "voice")
}

/// Polls the on-screen window list for windows of the voice input method.
///
/// Only the owner, window number, layer, alpha and bounds are read. Window
/// titles are never accessed, so no screen recording permission is required.
@MainActor
final class SystemVoiceOverlayDetector: VoiceOverlayDetecting {
    private struct WindowSnapshot: CustomStringConvertible {
        let number: Int
        let ownerPID: pid_t
        let ownerName: String
        let layer: Int
        let bounds: CGRect

        var description: String {
            "#\(number) pid=\(ownerPID) owner=\(ownerName) layer=\(layer) "
                + "bounds=\(Int(bounds.minX)),\(Int(bounds.minY)) \(Int(bounds.width))x\(Int(bounds.height))"
        }
    }

    private static let pollInterval: TimeInterval = 0.15

    private var baseline: Set<Int> = []
    private var timer: Timer?
    private var handler: (@MainActor (Bool) -> Void)?
    private var bundleIdentifier: String?
    private var lastVisible: Bool?

    func captureBaseline(bundleIdentifier: String?) {
        let windows = Self.voiceWindows(bundleIdentifier: bundleIdentifier)
        baseline = Set(windows.map(\.number))
        VoiceLog.logger.debug("overlay baseline: \(Self.describe(windows), privacy: .public)")
    }

    func start(bundleIdentifier: String?, handler: @escaping @MainActor (Bool) -> Void) {
        stop()

        self.bundleIdentifier = bundleIdentifier
        self.handler = handler

        // The first report arrives with the first tick, never synchronously from
        // start(), so the caller finishes its own bookkeeping first.
        let timer = Timer(timeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.poll()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        handler = nil
        lastVisible = nil
    }

    private func poll() {
        let windows = Self.voiceWindows(bundleIdentifier: bundleIdentifier)
        let overlays = windows.filter { !baseline.contains($0.number) }
        let visible = !overlays.isEmpty

        guard visible != lastVisible else { return }

        lastVisible = visible
        VoiceLog.logger.debug(
            "overlay visible=\(visible, privacy: .public) windows: \(Self.describe(windows), privacy: .public)"
        )
        handler?(visible)
    }

    private static func describe(_ windows: [WindowSnapshot]) -> String {
        windows.isEmpty ? "(none)" : windows.map(\.description).joined(separator: "; ")
    }

    /// On-screen windows owned by the voice input method's process. Windows are
    /// matched by process first and by owner name as a fallback, because the
    /// overlay may be drawn by a helper process.
    private static func voiceWindows(bundleIdentifier: String?) -> [WindowSnapshot] {
        var pids: Set<pid_t> = []
        if let bundleIdentifier {
            for app in NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier) {
                pids.insert(app.processIdentifier)
            }
        }

        guard
            let list = CGWindowListCopyWindowInfo(
                [.optionOnScreenOnly, .excludeDesktopElements],
                kCGNullWindowID
            ) as? [[String: Any]]
        else {
            return []
        }

        return list.compactMap { info in
            guard
                let number = info[kCGWindowNumber as String] as? Int,
                let ownerPID = info[kCGWindowOwnerPID as String] as? pid_t
            else {
                return nil
            }

            let ownerName = info[kCGWindowOwnerName as String] as? String ?? ""
            guard pids.contains(ownerPID) || isVoiceOwnerName(ownerName) else {
                return nil
            }

            let alpha = info[kCGWindowAlpha as String] as? Double ?? 1
            var bounds = CGRect.zero
            if let boundsInfo = info[kCGWindowBounds as String] as? NSDictionary {
                bounds = CGRect(dictionaryRepresentation: boundsInfo) ?? .zero
            }
            guard alpha > 0, bounds.width > 1, bounds.height > 1 else {
                return nil
            }

            return WindowSnapshot(
                number: number,
                ownerPID: ownerPID,
                ownerName: ownerName,
                layer: info[kCGWindowLayer as String] as? Int ?? 0,
                bounds: bounds
            )
        }
    }

    private static func isVoiceOwnerName(_ name: String) -> Bool {
        name.contains("豆包") || name.lowercased().contains("doubao")
    }
}
