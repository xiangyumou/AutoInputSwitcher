import AutoInputSwitcherCore
import Foundation

@main
struct CoreChecks {
    static func main() throws {
        try testRuleSetReturnsExactBundleRule()
        try testUpsertingRuleReplacesExistingBundleID()
        try testJSONRuleStoreLoadsEmptyRulesWhenFileDoesNotExist()
        try testJSONRuleStorePersistsRules()
        try testSwitchCounterDefaultsToZero()
        try testSwitchCounterPersistsIncrementedCount()
        try testApplicationListFilterMatchesNameAndBundleID()
        try testApplicationListFilterShowsOnlyConfiguredEntries()
        try testApplicationListFilterShowsOnlyUnconfiguredEntries()
        print("Core checks passed")
    }

    private static func testRuleSetReturnsExactBundleRule() throws {
        let terminal = AppRule(
            bundleIdentifier: "com.apple.Terminal",
            applicationName: "Terminal",
            inputSourceID: "com.apple.keylayout.US",
            inputSourceName: "U.S."
        )
        let ruleSet = RuleSet(rules: [terminal])

        try expectEqual(ruleSet.rule(forBundleIdentifier: "com.apple.Terminal"), terminal)
        try expectNil(ruleSet.rule(forBundleIdentifier: "com.apple.finder"))
    }

    private static func testUpsertingRuleReplacesExistingBundleID() throws {
        var ruleSet = RuleSet()
        ruleSet.upsert(
            AppRule(
                bundleIdentifier: "com.tencent.xinWeChat",
                applicationName: "WeChat",
                inputSourceID: "com.apple.keylayout.US",
                inputSourceName: "U.S."
            )
        )
        ruleSet.upsert(
            AppRule(
                bundleIdentifier: "com.tencent.xinWeChat",
                applicationName: "WeChat",
                inputSourceID: "com.apple.inputmethod.SCIM.Shuangpin",
                inputSourceName: "Shuangpin - Simplified"
            )
        )

        try expectEqual(ruleSet.rules.count, 1)
        try expectEqual(ruleSet.rules[0].inputSourceID, "com.apple.inputmethod.SCIM.Shuangpin")
    }

    private static func testJSONRuleStoreLoadsEmptyRulesWhenFileDoesNotExist() throws {
        let store = JSONRuleStore(url: temporaryRulesURL())

        try expectEqual(try store.load(), [])
    }

    private static func testJSONRuleStorePersistsRules() throws {
        let store = JSONRuleStore(url: temporaryRulesURL())
        let rules = [
            AppRule(
                bundleIdentifier: "com.apple.Terminal",
                applicationName: "Terminal",
                inputSourceID: "com.apple.keylayout.US",
                inputSourceName: "U.S."
            ),
            AppRule(
                bundleIdentifier: "com.tencent.xinWeChat",
                applicationName: "WeChat",
                inputSourceID: "com.apple.inputmethod.SCIM.Shuangpin",
                inputSourceName: "Shuangpin - Simplified"
            )
        ]

        try store.save(rules)

        try expectEqual(try store.load(), rules)
    }

    private static func temporaryRulesURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("rules.json")
    }

    private static func testSwitchCounterDefaultsToZero() throws {
        let defaults = temporaryDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let counter = SwitchCounter(defaults: defaults)

        try expectEqual(counter.count, 0)
    }

    private static func testSwitchCounterPersistsIncrementedCount() throws {
        let defaults = temporaryDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let counter = SwitchCounter(defaults: defaults)

        counter.recordSwitch()
        counter.recordSwitch()

        let reloaded = SwitchCounter(defaults: defaults)
        try expectEqual(reloaded.count, 2)
    }

    private static let suiteName = "AutoInputSwitcherCoreChecks.\(UUID().uuidString)"

    private static func temporaryDefaults() -> UserDefaults {
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            fatalError("Unable to create temporary UserDefaults suite")
        }
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    private static func testApplicationListFilterMatchesNameAndBundleID() throws {
        let terminal = ApplicationListEntry(
            displayName: "Terminal",
            bundleIdentifier: "com.apple.Terminal"
        )
        let weChat = ApplicationListEntry(
            displayName: "WeChat",
            bundleIdentifier: "com.tencent.xinWeChat"
        )

        let nameFilter = ApplicationListFilter(query: "term")
        let bundleFilter = ApplicationListFilter(query: "tencent")

        try expectEqual(nameFilter.includes(terminal), true)
        try expectEqual(nameFilter.includes(weChat), false)
        try expectEqual(bundleFilter.includes(terminal), false)
        try expectEqual(bundleFilter.includes(weChat), true)
    }

    private static func testApplicationListFilterShowsOnlyConfiguredEntries() throws {
        let terminal = ApplicationListEntry(
            displayName: "Terminal",
            bundleIdentifier: "com.apple.Terminal"
        )
        let weChat = ApplicationListEntry(
            displayName: "WeChat",
            bundleIdentifier: "com.tencent.xinWeChat"
        )
        let filter = ApplicationListFilter(
            scope: .configured,
            configuredBundleIdentifiers: ["com.tencent.xinWeChat"]
        )

        try expectEqual(filter.includes(terminal), false)
        try expectEqual(filter.includes(weChat), true)
    }

    private static func testApplicationListFilterShowsOnlyUnconfiguredEntries() throws {
        let terminal = ApplicationListEntry(
            displayName: "Terminal",
            bundleIdentifier: "com.apple.Terminal"
        )
        let weChat = ApplicationListEntry(
            displayName: "WeChat",
            bundleIdentifier: "com.tencent.xinWeChat"
        )
        let filter = ApplicationListFilter(
            scope: .unconfigured,
            configuredBundleIdentifiers: ["com.tencent.xinWeChat"]
        )

        try expectEqual(filter.includes(terminal), true)
        try expectEqual(filter.includes(weChat), false)
    }

    private static func expectEqual<T: Equatable>(_ actual: T, _ expected: T) throws {
        if actual != expected {
            throw CheckFailure("Expected \(expected), got \(actual)")
        }
    }

    private static func expectNil<T>(_ actual: T?) throws {
        if let actual {
            throw CheckFailure("Expected nil, got \(actual)")
        }
    }
}

struct CheckFailure: Error, CustomStringConvertible {
    let description: String

    init(_ description: String) {
        self.description = description
    }
}
