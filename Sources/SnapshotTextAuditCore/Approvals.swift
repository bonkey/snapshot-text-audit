import Foundation
import Yams

/// Findings a human has looked at and accepted, as file/text pairs.
///
/// ```yaml
/// approved:
///   - file: CalendarWidgetSnapshotTests/meeting-focus*
///     text: "*"
///     reason: event titles ellipsise by design in a glanceable widget
///   - file: GardienComposerSnapshotTests/composer-disabled-send-button*
///     text: Ask to unblock...
///     reason: text-field placeholder, not a truncated label
/// ```
///
/// `file` is a path, and `text` the recognised string; both are globs. A path pattern matches at any
/// depth, so a bare file name, any suffix, or the whole path all work — `roster.png`,
/// `CalendarWidget*`, `*/meeting-focus*`, or the full relative path `--approve` writes.
///
/// `--approve` writes the full path and the exact string, saying precisely what was accepted.
/// Widening it to a glob is a deliberate edit, and worth making: references get renamed wholesale —
/// a Dynamic Type segment inserted, a test renamed — without a pixel changing, and an entry pinned to
/// a full name goes stale the moment that happens.
///
/// `kind` is optional and never globbed. Left out, the entry covers every kind of finding for that
/// pair; set, it confines the approval, so accepting a truncation cannot quietly accept a missing
/// translation as well.
///
/// `reason` is an optional note and never affects matching. Prefer it to a `#` comment: `--approve`
/// decodes, merges and re-encodes, so hand-written comments do not survive a second run.
public struct Approvals: Sendable {
    public struct Entry: Sendable, Codable, Hashable {
        public var file: String
        public var text: String
        public var reason: String?
        public var kind: String?

        public init(file: String, text: String, reason: String? = nil, kind: String? = nil) {
            self.file = file
            self.text = text
            self.reason = reason
            self.kind = kind
        }

        func matches(file candidatePath: String, text candidateText: String, kind candidateKind: String) -> Bool {
            if let kind, kind != candidateKind { return false }
            return Self.matchesPath(pattern: file, path: candidatePath) && glob(text, candidateText)
        }

        /// Matches a pattern against a path at any depth.
        ///
        /// The pattern may be a bare file name, any suffix of the path, or the whole path, with or
        /// without globs — `roster.png`, `FriendsWidget*`, `*/roster*`, `**/Friends*/roster*` and an
        /// absolute path all work. Comparing against every path suffix is what buys that: writing an
        /// approval should not require knowing how deep the corpus happens to sit.
        static func matchesPath(pattern: String, path: String) -> Bool {
            let normalised = pattern.hasPrefix("**/") ? String(pattern.dropFirst(3)) : pattern
            let components = path.split(separator: "/").map(String.init)
            for start in components.indices {
                let suffix = components[start...].joined(separator: "/")
                // Flags are 0 on purpose: `*` crosses `/`, so `Friends*/roster*` spans directories.
                if normalised == suffix || fnmatch(normalised, suffix, 0) == 0 { return true }
            }
            return false
        }

        private func glob(_ pattern: String, _ value: String) -> Bool {
            pattern == value || fnmatch(pattern, value, 0) == 0
        }
    }

    private struct Document: Codable {
        var approved: [Entry]
    }

    public private(set) var entries: [Entry]
    public let url: URL?

    public init(entries: [Entry] = [], url: URL? = nil) {
        self.entries = entries
        self.url = url
    }

    public static func load(from url: URL) throws -> Approvals {
        let raw = try String(contentsOf: url, encoding: .utf8)
        guard !raw.trimmed().isEmpty else { return Approvals(url: url) }
        let document = try YAMLDecoder().decode(Document.self, from: raw)
        return Approvals(entries: document.approved, url: url)
    }

    public var count: Int { entries.count }

    public func approves(_ finding: Finding) -> Bool {
        let text = finding.line.text.trimmed()
        return entries.contains {
            $0.matches(file: finding.image.url.path, text: text, kind: finding.kind)
        }
    }

    /// The path as written into a new entry: relative to `base` when it sits underneath, absolute
    /// otherwise.
    ///
    /// Full and specific, because a generated entry should say exactly what was approved — widening
    /// it to a glob is a deliberate edit. Relative because the file gets committed, and an absolute
    /// path is true on one machine only.
    public static func path(for url: URL, relativeTo base: URL?) -> String {
        guard let base else { return url.path }
        let root = base.standardizedFileURL.path
        let full = url.standardizedFileURL.path
        guard full.hasPrefix(root + "/") else { return full }
        return String(full.dropFirst(root.count + 1))
    }

    public static func entry(for finding: Finding, reason: String?, relativeTo base: URL?) -> Entry {
        Entry(
            file: path(for: finding.image.url, relativeTo: base),
            text: finding.line.text.trimmed(),
            reason: reason,
            kind: finding.kind
        )
    }

    /// Merges `newEntries` in, dropping ones an existing entry already covers, and writes the file.
    ///
    /// Returns the number actually added. Merging rather than overwriting is what makes `--approve`
    /// safe to run repeatedly: hand-written globs and their reasons survive.
    @discardableResult
    public mutating func add(_ newEntries: [Entry]) -> Int {
        var added = 0
        for candidate in newEntries {
            let covered = entries.contains {
                $0.matches(file: candidate.file, text: candidate.text, kind: candidate.kind ?? "")
                    || ($0.file == candidate.file && $0.text == candidate.text && $0.kind == candidate.kind)
            }
            guard !covered else { continue }
            entries.append(candidate)
            added += 1
        }
        return added
    }

    public func write(to destination: URL, header: String? = nil) throws {
        let sorted = entries.sorted { ($0.file, $0.text) < ($1.file, $1.text) }
        let encoder = YAMLEncoder()
        // Without this the recognised text is escaped to \uXXXX, and the approvals file becomes
        // unreadable exactly where a human most needs to read it — the string being accepted.
        encoder.options.allowUnicode = true
        let yaml = try encoder.encode(Document(approved: sorted))
        let body = (header.map { $0 + "\n" } ?? "") + yaml
        try body.write(to: destination, atomically: true, encoding: .utf8)
    }

    /// Dotfile by default: this is tooling config living beside the code it describes, not a
    /// document anyone browses.
    public static let defaultFileName = ".snapshot-text-approved.yml"

    public static let defaultHeader = """
    # Findings that have been reviewed and accepted. Anything not listed here is reported.
    #
    #   file    path glob — matches at any depth, so "roster.png", "CalendarWidget*",
    #           "*/meeting-focus*" and a full relative path all work
    #   text    glob over the recognised string
    #   kind    truncated | untranslated | edge  (optional; omit to cover every kind)
    #   reason  optional note; never affects matching, purely for whoever reads this next
    #
    # --approve rewrites this file, so `#` comments do not survive it — put notes in `reason`.
    #
    # --approve writes the exact path and string. Widening to a glob is worth doing: references get
    # renamed without their pixels changing, and a pinned path goes stale when that happens.
    """
}
