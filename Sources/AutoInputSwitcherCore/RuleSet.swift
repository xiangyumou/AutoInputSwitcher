import Foundation

public struct RuleSet: Equatable, Sendable {
    public private(set) var rules: [AppRule]

    public init(rules: [AppRule] = []) {
        self.rules = rules
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
