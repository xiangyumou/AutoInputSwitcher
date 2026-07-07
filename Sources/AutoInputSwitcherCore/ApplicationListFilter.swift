import Foundation

public enum ApplicationListScope: String, Sendable {
    case all
    case configured
    case unconfigured
}

public struct ApplicationListEntry: Equatable, Sendable {
    public let displayName: String
    public let bundleIdentifier: String

    public init(displayName: String, bundleIdentifier: String) {
        self.displayName = displayName
        self.bundleIdentifier = bundleIdentifier
    }
}

public struct ApplicationListFilter: Sendable {
    public let query: String
    public let scope: ApplicationListScope
    public let configuredBundleIdentifiers: Set<String>

    public init(
        query: String = "",
        scope: ApplicationListScope = .all,
        configuredBundleIdentifiers: Set<String> = []
    ) {
        self.query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        self.scope = scope
        self.configuredBundleIdentifiers = configuredBundleIdentifiers
    }

    public func includes(_ entry: ApplicationListEntry) -> Bool {
        let isConfigured = configuredBundleIdentifiers.contains(entry.bundleIdentifier)

        if scope == .configured, !isConfigured {
            return false
        }

        if scope == .unconfigured, isConfigured {
            return false
        }

        guard !query.isEmpty else {
            return true
        }

        return entry.displayName.localizedCaseInsensitiveContains(query)
            || entry.bundleIdentifier.localizedCaseInsensitiveContains(query)
    }
}
