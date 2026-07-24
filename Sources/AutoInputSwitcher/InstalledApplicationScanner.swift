import AppKit
import Foundation

struct InstalledApplicationScanner: @unchecked Sendable {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func scan() -> [InstalledApplication] {
        let urls = searchRoots()
        var applicationsByBundleID: [String: InstalledApplication] = [:]

        for rootURL in urls where fileManager.fileExists(atPath: rootURL.path) {
            for applicationURL in applicationURLs(under: rootURL) {
                guard let application = application(at: applicationURL) else {
                    continue
                }

                applicationsByBundleID[application.bundleIdentifier] = application
            }
        }

        return applicationsByBundleID.values.sorted {
            let comparison = $0.name.localizedCaseInsensitiveCompare($1.name)
            if comparison == .orderedSame {
                return $0.bundleIdentifier < $1.bundleIdentifier
            }
            return comparison == .orderedAscending
        }
    }

    private func searchRoots() -> [URL] {
        var urls: [URL] = [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            URL(fileURLWithPath: "/System/Applications", isDirectory: true),
            URL(fileURLWithPath: "/System/Library/CoreServices", isDirectory: true),
            URL(fileURLWithPath: "/System/Library/CoreServices/Applications", isDirectory: true)
        ]

        if let userApplications = fileManager.urls(
            for: .applicationDirectory,
            in: .userDomainMask
        ).first {
            urls.append(userApplications)
        }

        return urls
    }

    private func applicationURLs(under rootURL: URL) -> [URL] {
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isPackageKey]
        guard let enumerator = fileManager.enumerator(
            at: rootURL,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var urls: [URL] = []
        for case let url as URL in enumerator {
            guard url.pathExtension == "app" else {
                continue
            }

            urls.append(url)
            enumerator.skipDescendants()
        }
        return urls
    }

    private func application(at url: URL) -> InstalledApplication? {
        guard
            let bundle = Bundle(url: url),
            let bundleIdentifier = bundle.bundleIdentifier,
            !bundleIdentifier.isEmpty
        else {
            return nil
        }

        let name = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? bundle.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? url.deletingPathExtension().lastPathComponent

        return InstalledApplication(
            name: name,
            bundleIdentifier: bundleIdentifier,
            url: url
        )
    }
}
