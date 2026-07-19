import Foundation

/// Identity of an accepted finding.
///
/// Deliberately excludes the file name. Snapshot references get renamed wholesale — trait segments
/// added, tests renamed — without a single pixel changing; a file-name key would go stale on such a
/// commit and report every accepted finding as new. Including the recognised `text` is intentional in
/// the other direction: if a translation changes, the finding should come back for review.
public struct BaselineKey: Sendable, Hashable {
    public let suite: String
    public let test: String
    public let geometry: String
    public let language: String
    public let kind: String
    public let text: String

    public init(suite: String, test: String, geometry: String, language: String, kind: String, text: String) {
        self.suite = suite
        self.test = test
        self.geometry = geometry
        self.language = language
        self.kind = kind
        self.text = text
    }
}

/// A newline-delimited file of accepted findings, one `|`-separated record per line.
///
/// Every field except `kind` is a glob, so a record can be as tight or as broad as the reason
/// warrants. `* | *` for geometry and language is the common case — an intentional placeholder is
/// intentional in all six languages — and a glob on `text` covers a whole class:
///
///     CalendarWidgetSnapshotTests | meeting-focus | * | * | truncated | * | titles truncate by design
///
/// Globbing `text` is the broader, more durable choice: it survives fixture copy changing, but it
/// also accepts a *new* truncation in the same test. Spell the text out when that matters.
public struct Baseline: Sendable {
    private struct Entry: Sendable {
        let suite: String
        let test: String
        let geometry: String
        let language: String
        let kind: String
        let text: String

        func matches(_ key: BaselineKey) -> Bool {
            glob(suite, key.suite)
                && glob(test, key.test)
                && glob(geometry, key.geometry)
                && glob(language, key.language)
                && kind == key.kind
                && glob(text, key.text)
        }

        private func glob(_ pattern: String, _ value: String) -> Bool {
            pattern == value || fnmatch(pattern, value, 0) == 0
        }
    }

    private let entries: [Entry]
    public let path: URL?

    public init(entries: [String] = [], path: URL? = nil) {
        self.path = path
        self.entries = entries.compactMap(Self.parse)
    }

    public static func load(from url: URL) throws -> Baseline {
        let raw = try String(contentsOf: url, encoding: .utf8)
        return Baseline(entries: raw.components(separatedBy: .newlines), path: url)
    }

    private static func parse(_ line: String) -> Entry? {
        let trimmed = line.trimmed()
        guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { return nil }
        // suite | test | geometry | language | kind | text [| reason]
        let fields = trimmed.components(separatedBy: "|").map { $0.trimmed() }
        guard fields.count >= 6 else { return nil }
        return Entry(
            suite: fields[0], test: fields[1], geometry: fields[2],
            language: fields[3], kind: fields[4], text: fields[5]
        )
    }

    public func excludes(_ key: BaselineKey) -> Bool {
        entries.contains { $0.matches(key) }
    }

    public var count: Int { entries.count }

    /// Renders findings as baseline records, ready to append to the file.
    ///
    /// Emits one record per distinct text so a human sees what is being accepted; collapsing to a
    /// `*` is a deliberate edit, not something to be talked into by a generator.
    public static func record(for finding: Finding, reason: String) -> String {
        let key = finding.baselineKey
        return [key.suite, key.test, "*", "*", key.kind, key.text, reason]
            .joined(separator: " | ")
    }
}
