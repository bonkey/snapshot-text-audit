import ArgumentParser
import Foundation
import SnapshotTextAuditCore

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("error: \(message)\n".utf8))
    exit(2)
}

private func parseImageBox(_ raw: String) throws -> TerminalReport.ImageBox {
    let parts = raw.lowercased().split(separator: "x").compactMap { Int($0) }
    guard parts.count == 2 else {
        throw ValidationError("--image-size expects <width>x<height>, got \(raw)")
    }
    return TerminalReport.ImageBox(width: parts[0], height: parts[1])
}

private func fileURL(_ raw: String) -> URL {
    URL(fileURLWithPath: raw)
}

struct SnapshotTextAudit: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "snapshot-text-audit",
        abstract: "Find truncated, clipped and untranslated text in snapshot reference images.",
        discussion: """
        OCR results are reused between runs, keyed on image content, from \
        ~/Library/Caches/snapshot-text-audit. A changed image is always rescanned.

        Exits 0 when there are no findings or only informational ones, 1 when truncated or \
        untranslated text is found, and 2 on unreadable input.
        """
    )

    @Argument(help: "Directory of .png references (default: current directory).")
    var root: String?

    @Option(help: ArgumentHelp(
        "Only files git reports as changed vs <base> (e.g. origin/main).",
        valueName: "base"
    ))
    var changed: String?

    @Option(help: ArgumentHelp("Only files matching (repeatable).", valueName: "glob"))
    var include: [String] = []

    @Option(help: ArgumentHelp("Skip files matching (repeatable).", valueName: "glob"))
    var exclude: [String] = []

    @Flag(inversion: .prefixedNo, help: "Run the ellipsis check.")
    var truncation = true

    @Flag(inversion: .prefixedNo, help: "Run the untranslated-text check.")
    var untranslated = true

    @Flag(help: "Include edge-proximity findings (informational, noisy).")
    var edges = false

    @Option(help: "Language treated as the source of truth.")
    var baselineLanguage = "en"

    @Flag(inversion: .prefixedNo, help: """
    Show each snapshot with its findings — inline in the terminal (iTerm2 only) and embedded in \
    the Markdown report. When neither flag is given, the terminal stays text-only and the \
    Markdown report keeps its images.
    """)
    var images: Bool?

    @Option(help: "Scale inline images (e.g. 2 for double). Implies --images.")
    var zoom: Double?

    @Option(
        name: .customLong("image-size"),
        help: ArgumentHelp(
            "Fit box in px for inline images (default: 400x700). Implies --images.",
            valueName: "w>x<h"
        ),
        transform: parseImageBox
    )
    var imageSize: TerminalReport.ImageBox?

    @Option(
        help: ArgumentHelp(
            "Also write a Markdown report, links relative to <file> so it travels with the repository.",
            valueName: "file"
        ),
        transform: fileURL
    )
    var markdown: URL?

    @Option(
        name: [.customLong("approved"), .customLong("baseline")],
        help: ArgumentHelp(
            "YAML of reviewed-and-accepted findings to ignore (default: ./\(Approvals.defaultFileName)).",
            valueName: "file"
        ),
        transform: fileURL
    )
    var approved: URL?

    @Flag(help: "Add everything found to the approved file, then exit 0.")
    var approve = false

    @Option(help: "Reason recorded by --approve.")
    var reason: String?

    @Flag(help: "Findings only.")
    var quiet = false

    @Flag(inversion: .prefixedNo, help: "Reuse OCR results between runs.")
    var cache = true

    @Flag(help: "Delete the cache, then carry on.")
    var clearCache = false

    func validate() throws {
        if let zoom, zoom <= 0 {
            throw ValidationError("--zoom needs a positive number")
        }
    }

    func run() throws {
        let rootURL = URL(fileURLWithPath: root ?? FileManager.default.currentDirectoryPath)
            .standardizedFileURL
        guard FileManager.default.fileExists(atPath: rootURL.path) else {
            fail("no such directory: \(rootURL.path)")
        }

        // One flag, two surfaces, different defaults: unset draws nothing in the terminal —
        // scrollback is expensive — but everything in the Markdown report, where the images are
        // the point of writing one. Asking to size or zoom them is asking to see them.
        let terminalImages = images ?? (zoom != nil || imageSize != nil)
        let markdownImages = images ?? true

        let style = TerminalStyle.detect(imagesRequested: terminalImages)
        let imageBox = (imageSize ?? TerminalReport.ImageBox()).scaled(by: zoom ?? 1.0)
        var report = TerminalReport(style: style, box: imageBox)

        var urls: [URL]
        if let base = changed {
            guard let changed = ImageSource.changed(under: rootURL, base: base, repository: rootURL) else {
                fail("git diff against \(base) failed — is \(rootURL.path) inside a repository?")
            }
            urls = changed
            if !quiet { report.note("scope: files changed vs \(base)") }
        } else {
            urls = ImageSource.all(under: rootURL)
        }
        urls = ImageSource.filter(urls, include: include, exclude: exclude)

        guard !urls.isEmpty else {
            if !quiet { report.note("no images to scan"); report.flush() }
            Foundation.exit(0)
        }

        // Relative to the working directory, not to <root>: the file gets committed next to the
        // code that owns it, and deriving it from <root> drops it somewhere different for every
        // scope you scan.
        let workingDirectory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let approvedURL = approved
            ?? workingDirectory.appendingPathComponent(Approvals.defaultFileName)

        var approvals = Approvals(url: approvedURL)
        if FileManager.default.fileExists(atPath: approvedURL.path) {
            do {
                approvals = try Approvals.load(from: approvedURL)
            } catch {
                fail("could not read \(approvedURL.lastPathComponent): \(error)")
            }
        }

        let ocrCache = OCRCache()
        if clearCache {
            try? FileManager.default.removeItem(at: ocrCache.directory)
            if !quiet { report.note("cleared \(ocrCache.directory.path)") }
        }

        if !quiet {
            report.note("scanning \(urls.count) image\(urls.count == 1 ? "" : "s")…")
            report.flush()
            report = TerminalReport(style: style, box: imageBox)
        }

        let languages = ["en-US", "fr-FR", "es-ES", "pt-BR", "de-DE", "it-IT"]
        let (scanned, failures, cacheHits) = OCR.scanAll(
            urls: urls,
            languages: languages,
            cache: cache ? ocrCache : nil
        )

        var findings: [Finding] = []
        if truncation { findings += Checks.truncated(in: scanned) }
        if untranslated {
            findings += Checks.untranslated(in: scanned, baselineLanguage: baselineLanguage)
        }
        if edges {
            findings += Checks.edges(in: scanned, baselineLanguage: baselineLanguage)
        }

        let approvedCount = findings.count { approvals.approves($0) }
        findings = findings.filter { !approvals.approves($0) }

        if approve {
            let added = approvals.add(findings.map {
                Approvals.entry(for: $0, reason: reason, relativeTo: workingDirectory)
            })
            do {
                try approvals.write(to: approvedURL, header: Approvals.defaultHeader)
            } catch {
                fail("could not write \(approvedURL.path): \(error)")
            }
            print("approved \(added) finding\(added == 1 ? "" : "s") → \(approvedURL.path)")
            if added > 0 { print("edit the file to widen a glob or say why each one is acceptable") }
            Foundation.exit(0)
        }

        let errors = findings.filter { $0.severity == .error }
        let infos = findings.filter { $0.severity == .info }

        for (title, group) in [("Findings", errors), ("Informational — needs a human", infos)]
            where !group.isEmpty
        {
            report.heading(title)
            report.rule()
            for finding in group.sorted(by: { $0.image.url.path < $1.image.url.path }) {
                report.finding(finding, showImage: terminalImages)
            }
        }

        var summary = "\(scanned.count) scanned · \(errors.count) finding\(errors.count == 1 ? "" : "s")"
        if !infos.isEmpty { summary += " · \(infos.count) informational" }
        if approvedCount > 0 { summary += " · \(approvedCount) approved" }
        if !failures.isEmpty { summary += " · \(failures.count) unreadable" }
        if cacheHits > 0 { summary += " · \(cacheHits) cached" }

        if let markdownURL = markdown {
            let rendered = MarkdownReport(
                destination: markdownURL,
                root: rootURL,
                includeImages: markdownImages
            )
            .render(findings: findings, summary: summary)
            do {
                try rendered.write(to: markdownURL, atomically: true, encoding: .utf8)
            } catch {
                fail("could not write \(markdownURL.path): \(error)")
            }
            if !quiet { report.note("wrote \(markdownURL.path)") }
        }

        if !quiet { report.heading(summary) }

        report.flush()
        Foundation.exit(errors.isEmpty ? 0 : 1)
    }
}

SnapshotTextAudit.main()
