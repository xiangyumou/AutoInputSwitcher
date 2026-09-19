import Foundation

/// In-memory collection of per-application input source rules.
///
/// Lookup semantics are "first match wins": whenever the same bundle identifier
/// appears more than once, the earliest entry is the effective rule. Use
/// init(normalizing:) when loading from disk so duplicates are collapsed before
/// they reach the user interface.
public struct RuleSet: Equatable, Sendable {
    /// Sentinel used by the user interface to mean "do not switch for this app".
    public static let noSwitchInputSourceID = "-"

    public private(set) var rules: [AppRule]

    public init(rules: [AppRule] = []) {
        self.rules = rules
    }

    /// Builds a rule set from persisted rules, dropping invalid entries and
    /// keeping only the first rule seen for each bundle identifier.
    public init(normalizing rules: [AppRule]) {
        var seenBundleIdentifiers: Set<String> = []
        var normalized: [AppRule] = []

        for rule in rules where Self.isValid(rule) {
            guard seenBundleIdentifiers.insert(rule.bundleIdentifier).inserted else {
                continue
            }
            normalized.append(rule)
        }

        self.rules = normalized
    }

    /// A rule is usable only when both identifiers are present and neither is the
    /// "-" placeholder that the picker uses to mean "no rule".
    public static func isValid(_ rule: AppRule) -> Bool {
        isValidIdentifier(rule.bundleIdentifier) && isValidIdentifier(rule.inputSourceID)
    }

    public static func isValidIdentifier(_ identifier: String) -> Bool {
        let trimmed = identifier.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && trimmed != noSwitchInputSourceID
    }

    public func rule(forBundleIdentifier bundleIdentifier: String) -> AppRule? {
        rules.first { $0.bundleIdentifier == bundleIdentifier }
    }

    public mutating func upsert(_ rule: AppRule) {
        if let index = rules.firstIndex(where: { $0.bundleIdentifier == rule.bundleIdentifier }) {
            rules[index] = rule
        } else {
            rules.append(rule)
        }
    }

    @discardableResult
    public mutating func remove(bundleIdentifier: String) -> AppRule? {
        guard let index = rules.firstIndex(where: { $0.bundleIdentifier == bundleIdentifier }) else {
            return nil
        }

        return rules.remove(at: index)
    }
}
