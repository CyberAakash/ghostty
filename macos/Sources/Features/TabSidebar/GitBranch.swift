import Foundation

/// Finds the current git branch by reading `.git/HEAD` directly. No subprocess is spawned, and
/// the lookup of a directory's HEAD file is cached, so refreshing many tabs stays cheap.
enum GitBranch {
    private static var headPathCache: [String: String] = [:]

    static func current(inDirectory directory: String) -> String? {
        guard let headPath = headPath(for: directory),
              let head = try? String(contentsOfFile: headPath, encoding: .utf8) else {
            return nil
        }

        let text = head.trimmingCharacters(in: .whitespacesAndNewlines)
        let prefix = "ref: refs/heads/"
        if text.hasPrefix(prefix) { return String(text.dropFirst(prefix.count)) }
        // Detached HEAD holds a bare commit hash.
        return text.count >= 7 ? String(text.prefix(7)) : nil
    }

    private static func headPath(for directory: String) -> String? {
        if let cached = headPathCache[directory], FileManager.default.fileExists(atPath: cached) {
            return cached
        }

        var url = URL(fileURLWithPath: directory)
        for _ in 0..<24 {
            let dotGit = url.appendingPathComponent(".git")
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: dotGit.path, isDirectory: &isDir) {
                let head: String?
                if isDir.boolValue {
                    head = dotGit.appendingPathComponent("HEAD").path
                } else {
                    // Worktrees and submodules: `.git` is a file containing `gitdir: <path>`.
                    head = gitDir(fromFile: dotGit, relativeTo: url).map { $0 + "/HEAD" }
                }

                if let head {
                    if headPathCache.count > 128 { headPathCache.removeAll() }
                    headPathCache[directory] = head
                    return head
                }
                return nil
            }

            let parent = url.deletingLastPathComponent()
            if parent.path == url.path { break }
            url = parent
        }

        return nil
    }

    private static func gitDir(fromFile file: URL, relativeTo base: URL) -> String? {
        guard let text = try? String(contentsOf: file, encoding: .utf8) else { return nil }
        let prefix = "gitdir: "
        guard let line = text.split(separator: "\n").first, line.hasPrefix(prefix) else { return nil }
        let path = String(line.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
        if path.hasPrefix("/") { return path }
        return base.appendingPathComponent(path).standardized.path
    }
}

/// Added / removed line counts for a repository, like Warp's diff stats badge. It runs
/// `git diff --shortstat` on a background queue, only when asked (Expanded density), and caches
/// the answer so a refresh never waits on git.
final class GitDiffStats {
    static let shared = GitDiffStats()

    private struct Entry {
        var stats: TabSidebarDiffStats?
        var fetchedAt: Date
    }

    private static let timeToLive: TimeInterval = 10
    private var cache: [String: Entry] = [:]
    private var inFlight: Set<String> = []
    private let queue = DispatchQueue(label: "com.mitchellh.ghostty.tabsidebar.git", qos: .utility)

    /// The cached stats for `directory`. A stale or missing entry starts one background fetch and
    /// `onChange` fires on the main queue only if the answer differs from what was cached.
    func stats(forDirectory directory: String, onChange: @escaping () -> Void) -> TabSidebarDiffStats? {
        let entry = cache[directory]
        let isStale = entry.map { Date().timeIntervalSince($0.fetchedAt) > Self.timeToLive } ?? true
        if isStale && !inFlight.contains(directory) {
            inFlight.insert(directory)
            queue.async { [weak self] in
                let result = Self.run(directory)
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.inFlight.remove(directory)
                    let changed = self.cache[directory]?.stats != result
                    self.cache[directory] = Entry(stats: result, fetchedAt: Date())
                    if changed { onChange() }
                }
            }
        }
        return entry?.stats
    }

    private static func run(_ directory: String) -> TabSidebarDiffStats? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-C", directory, "diff", "--shortstat", "HEAD"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0, let text = String(data: data, encoding: .utf8) else { return nil }
        return parse(text)
    }

    /// Parses " 3 files changed, 12 insertions(+), 4 deletions(-)". Empty output means a clean tree.
    static func parse(_ text: String) -> TabSidebarDiffStats? {
        func number(before word: String) -> Int {
            guard let range = text.range(of: word) else { return 0 }
            let prefix = text[..<range.lowerBound].trimmingCharacters(in: .whitespaces)
            return Int(prefix.split(separator: " ").last ?? "") ?? 0
        }
        let added = number(before: "insertion")
        let removed = number(before: "deletion")
        return added == 0 && removed == 0 ? nil : TabSidebarDiffStats(added: added, removed: removed)
    }
}
