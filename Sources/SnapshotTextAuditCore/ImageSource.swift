import Foundation

public enum ImageSource {
    /// Every `.png` under `root`, sorted.
    public static func all(under root: URL) -> [URL] {
        guard let walker = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        return walker
            .compactMap { $0 as? URL }
            .filter { $0.pathExtension.lowercased() == "png" }
            .sorted { $0.path < $1.path }
    }

    /// Files that differ from `base`, restricted to `root`.
    ///
    /// Scoping by git rather than by modification time is deliberate: a checkout or rebase rewrites
    /// mtimes wholesale, and a rename moves a path without touching pixels. `--diff-filter=ACMR`
    /// keeps additions, copies, modifications and renames; a renamed file with identical content
    /// costs one scan and reports nothing.
    public static func changed(under root: URL, base: String, repository: URL) -> [URL]? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [
            "git", "-C", repository.path,
            "diff", "--name-only", "--diff-filter=ACMR", base, "--", root.path,
        ]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do { try process.run() } catch { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }

        return String(decoding: data, as: UTF8.self)
            .components(separatedBy: .newlines)
            .filter { $0.hasSuffix(".png") }
            .map { repository.appendingPathComponent($0) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
            .sorted { $0.path < $1.path }
    }

    /// Applies glob filters to file names. Include wins first, then exclude removes.
    public static func filter(_ urls: [URL], include: [String], exclude: [String]) -> [URL] {
        urls.filter { url in
            let name = url.lastPathComponent
            let suite = url.deletingLastPathComponent().lastPathComponent
            let candidates = [name, "\(suite)/\(name)"]

            if !include.isEmpty {
                guard include.contains(where: { pattern in
                    candidates.contains { matches(pattern: pattern, $0) }
                }) else { return false }
            }
            if exclude.contains(where: { pattern in
                candidates.contains { matches(pattern: pattern, $0) }
            }) { return false }
            return true
        }
    }

    static func matches(pattern: String, _ value: String) -> Bool {
        fnmatch(pattern, value, 0) == 0
    }
}
