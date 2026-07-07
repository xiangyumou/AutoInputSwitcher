import Foundation

public struct JSONRuleStore: Sendable {
    public let url: URL

    public init(url: URL) {
        self.url = url
    }

    public static func applicationSupportStore(
        appName: String = "AutoInputSwitcher"
    ) -> JSONRuleStore {
        let baseURL = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]
        let url = baseURL
            .appendingPathComponent(appName, isDirectory: true)
            .appendingPathComponent("rules.json")
        return JSONRuleStore(url: url)
    }

    public func load() throws -> [AppRule] {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return []
        }

        let data = try Data(contentsOf: url)
        return try Self.decoder.decode([AppRule].self, from: data)
    }

    public func save(_ rules: [AppRule]) throws {
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )

        let data = try Self.encoder.encode(rules)
        try data.write(to: url, options: [.atomic])
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    private static let decoder = JSONDecoder()
}
