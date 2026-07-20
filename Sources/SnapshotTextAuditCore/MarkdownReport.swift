import Foundation

/// A Markdown report — the same verdicts the terminal prints, laid out for a browser.
///
/// Findings are grouped by the folder holding the reference, because that is how a snapshot corpus
/// is organised: one folder per test suite, and a folder that goes bad usually goes bad in several
/// places at once. One `<details>` per folder holds every image in it, so a run with two hundred
/// hits stays a page you can read, and opening a suite shows all of its evidence at once rather than
/// asking for a click per finding.
///
/// Inside a fold, findings are collected under the reference they came from and the image is drawn
/// once. Several findings on one render is the ordinary case — a screen that overflows usually
/// overflows in more than one place — and inlining the same PNG once per finding would repeat it.
///
/// Every link is relative to the file the report is written to, so the document travels with the
/// repository — commit it, attach it to a CI job, open it in a viewer, and the images still resolve.
public struct MarkdownReport {
    private let directory: URL
    private let root: URL

    /// - Parameters:
    ///   - destination: the file this report will be written to. Links are relative to it.
    ///   - root: the scanned directory. Headings are named relative to it, so a folder reads the
    ///     same whether the report lands beside the corpus or in a build directory away from it.
    public init(destination: URL, root: URL) {
        directory = destination.deletingLastPathComponent()
        self.root = root
    }

    public func render(findings: [Finding], summary: String) -> String {
        let groups = Dictionary(grouping: findings) { heading(for: $0.image.url.deletingLastPathComponent()) }

        var out = "# Snapshot text audit\n\n\(Self.escape(summary))\n"
        guard !groups.isEmpty else {
            return out + "\nNothing to report.\n"
        }

        var slugs = SlugTable()
        let sections = groups.keys.sorted().map { folder in
            (folder: folder, anchor: slugs.slug(for: folder), findings: groups[folder] ?? [])
        }

        out += "\n## Contents\n\n"
        for section in sections {
            out += "- [\(Self.escape(section.folder))](#\(section.anchor))"
                + " — \(Self.tally(section.findings))\n"
        }

        for section in sections {
            out += "\n## \(Self.escape(section.folder))\n\n" + fold(section.findings)
        }

        return out
    }

    /// Names a folder the way the corpus is organised. A report filed outside the scanned tree
    /// would otherwise head its sections with a run of `..`, which says where the report sits
    /// rather than which suite went bad.
    private func heading(for folder: URL) -> String {
        let relative = Self.relativePath(from: root, to: folder)
        guard relative != ".", !relative.hasPrefix("..") else { return folder.lastPathComponent }
        return relative
    }

    /// One fold for a whole folder, holding every reference in it.
    private func fold(_ findings: [Finding]) -> String {
        let byImage = Dictionary(grouping: findings, by: { $0.image.url })
        let references = byImage.keys.sorted { $0.lastPathComponent < $1.lastPathComponent }

        var out = """
        <details>
        <summary>\(Self.tally(findings)) · \(references.count) \
        reference\(references.count == 1 ? "" : "s")</summary>


        """

        for url in references {
            let href = self.href(for: url)
            let file = Self.escape(url.lastPathComponent)
            out += "### [\(file)](\(href))\n\n"

            for finding in (byImage[url] ?? []).sorted(by: { $0.kind < $1.kind }) {
                let language = finding.image.name.language.map { " `\($0)`" } ?? ""
                out += "- <code>\(finding.kind.uppercased())</code>\(language) "
                    + "\(Self.escape(finding.headline))\n"
            }

            out += "\n[![\(file)](\(href))](\(href))\n\n"
        }

        return out + "</details>\n"
    }

    /// A link target for a reference.
    ///
    /// Relative wherever the report and the corpus share a root, which is the case worth optimising
    /// for — the document then travels with the repository. Otherwise a `file://` URL rather than a
    /// bare absolute path: markdown reads a leading `/` as site-root-relative, so `/Users/…` would
    /// resolve against wherever the document is being served rather than against the disk.
    private func href(for url: URL) -> String {
        let path = Self.relativePath(from: directory, to: url)
        guard path.hasPrefix("/") else { return Self.encode(path) }
        return URL(fileURLWithPath: path).absoluteString
    }

    private static func tally(_ findings: [Finding]) -> String {
        let errors = findings.count { $0.severity == .error }
        let infos = findings.count { $0.severity == .info }
        var parts = [String]()
        if errors > 0 { parts.append("\(errors) finding\(errors == 1 ? "" : "s")") }
        if infos > 0 { parts.append("\(infos) informational") }
        return parts.joined(separator: ", ")
    }

    /// Neutralises text that came out of an image. Recognised copy is arbitrary — it contains
    /// underscores, asterisks and angle brackets — and none of it should be read as markup.
    static func escape(_ text: String) -> String {
        var out = ""
        for character in text {
            switch character {
            case "&": out += "&amp;"
            case "<": out += "&lt;"
            case ">": out += "&gt;"
            case "\\", "`", "*", "_", "[", "]", "(", ")", "#", "|": out += "\\\(character)"
            default: out.append(character)
            }
        }
        return out
    }

    static func encode(_ path: String) -> String {
        path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? path
    }

    /// The path of `target` as written from `base`, walking up with `..` where the two diverge.
    ///
    /// Falls back to the absolute path when they share no root, which keeps a report written outside
    /// the repository pointing at something real rather than at nothing.
    static func relativePath(from base: URL, to target: URL) -> String {
        let from = base.standardizedFileURL.resolvingSymlinksInPath().pathComponents
        let to = target.standardizedFileURL.resolvingSymlinksInPath().pathComponents

        var shared = 0
        while shared < from.count, shared < to.count, from[shared] == to[shared] { shared += 1 }
        guard shared > 1 else { return target.standardizedFileURL.path }

        let up = Array(repeating: "..", count: from.count - shared)
        let down = to[shared...]
        let components = up + down
        return components.isEmpty ? "." : components.joined(separator: "/")
    }

    /// GitHub-style heading anchors, with the disambiguating suffix GitHub itself appends when two
    /// headings reduce to the same slug — `App/Widgets` and `App Widgets` do.
    private struct SlugTable {
        private var seen = [String: Int]()

        mutating func slug(for heading: String) -> String {
            let base = heading.lowercased()
                .replacingOccurrences(of: " ", with: "-")
                .filter { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
            let count = seen[base, default: 0]
            seen[base] = count + 1
            return count == 0 ? base : "\(base)-\(count)"
        }
    }
}
