import AppKit
import Foundation

struct InstalledApplication: Identifiable, Equatable {
    var id: String { bundleIdentifier }

    let name: String
    let bundleIdentifier: String
    let url: URL
    let icon: NSImage
}
