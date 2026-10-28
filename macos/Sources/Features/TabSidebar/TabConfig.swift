import Foundation

/// A saved way to open a tab (name, directory, command), like Warp's tab configs. Stored as plain
/// JSON in `~/.config/ghostty/tab-configs.json` so it can be edited by hand and kept in dotfiles.
struct TabConfig: Codable, Equatable, Identifiable {
    var name: String
    var directory: String?
    var command: String?

    var id: String { name }
}

enum TabConfigStore {
    static var url: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/ghostty/tab-configs.json")
    }

    static func load() -> [TabConfig] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([TabConfig].self, from: data)) ?? []
    }

    /// Adds (or replaces, by name) a config.
    static func save(_ config: TabConfig) {
        var all = load().filter { $0.name != config.name }
        all.append(config)
        write(all)
    }

    /// Creates the file with an example if it does not exist yet, and returns its URL for editing.
    static func ensureFileExists() -> URL {
        if !FileManager.default.fileExists(atPath: url.path) {
            write([TabConfig(name: "Example: dev shell", directory: "~/", command: nil)])
        }
        return url
    }

    private static func write(_ configs: [TabConfig]) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(configs) else { return }
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }
}
