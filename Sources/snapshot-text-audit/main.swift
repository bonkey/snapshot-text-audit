import Foundation
import SnapshotTextAuditCore

let usage = """
snapshot-text-audit — find truncated, clipped and untranslated text in snapshot reference images

USAGE
  snapshot-text-audit [<root>] [options]

  <root>  directory of .png references (default: current directory)

SCOPE
  --changed [<base>]     only files git reports as changed vs <base> (default: origin/main)
  --include <glob>       only files matching (repeatable)
  --exclude <glob>       skip files matching (repeatable)

CHECKS
  --no-truncation        skip the ellipsis check
  --no-untranslated      skip the untranslated-text check
  --edges                include edge-proximity findings (informational, noisy)
  --baseline-language    language treated as the source of truth (default: en)

OUTPUT
  --images               draw the snapshot inline (iTerm2 only)
  --zoom <factor>        scale inline images (default: 1.0, e.g. 2 for double)
  --image-size <w>x<h>   fit box in px for inline images (default: 400x700)
  --approved <file>      YAML of reviewed-and-accepted findings to ignore
                         (default: snapshot-text-approved.yml beside <root>)
  --approve              add everything found to that file, then exit 0
  --reason <text>        reason recorded by --approve
  --quiet                findings only

EXIT
  0  no findings, or only informational ones
  1  truncated or untranslated text found
  2  bad usage or unreadable input
"""

struct Options {
    var root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    var changedBase: String?
    var include: [String] = []
    var exclude: [String] = []
    var checkTruncation = true
    var checkUntranslated = true
    var checkEdges = false
    var baselineLanguage = "en"
    var images = false
    var zoom: Double?
    var box = TerminalReport.ImageBox()
    var approvedFile: URL?
    var approve = false
    var reason: String?
    var quiet = false
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("error: \(message)\n".utf8))
    exit(2)
}

var options = Options()
var arguments = Array(CommandLine.arguments.dropFirst())
var positional: [String] = []

var index = 0
while index < arguments.count {
    let argument = arguments[index]
    func value(_ name: String) -> String {
        index += 1
        guard index < arguments.count else { fail("\(name) needs a value") }
        return arguments[index]
    }

    switch argument {
    case "-h", "--help": print(usage); exit(0)
    case "--changed":
        if index + 1 < arguments.count, !arguments[index + 1].hasPrefix("-") {
            options.changedBase = value("--changed")
        } else {
            options.changedBase = "origin/main"
        }
    case "--include": options.include.append(value("--include"))
    case "--exclude": options.exclude.append(value("--exclude"))
    case "--no-truncation": options.checkTruncation = false
    case "--no-untranslated": options.checkUntranslated = false
    case "--edges": options.checkEdges = true
    case "--baseline-language": options.baselineLanguage = value("--baseline-language")
    case "--images": options.images = true
    case "--zoom":
        guard let factor = Double(value("--zoom")), factor > 0 else { fail("--zoom needs a positive number") }
        options.zoom = factor
    case "--image-size":
        let raw = value("--image-size")
        let parts = raw.lowercased().split(separator: "x").compactMap { Int($0) }
        guard parts.count == 2 else { fail("--image-size expects <width>x<height>, got \(raw)") }
        options.box = TerminalReport.ImageBox(width: parts[0], height: parts[1])
    case "--approved", "--baseline": options.approvedFile = URL(fileURLWithPath: value("--approved"))
    case "--approve": options.approve = true
    case "--reason": options.reason = value("--reason")
    case "--quiet": options.quiet = true
    default:
        if argument.hasPrefix("-") { fail("unknown option \(argument)") }
        positional.append(argument)
    }
    index += 1
}

if options.zoom != nil { options.images = true }

if let first = positional.first {
    options.root = URL(fileURLWithPath: first).standardizedFileURL
}
guard FileManager.default.fileExists(atPath: options.root.path) else {
    fail("no such directory: \(options.root.path)")
}

let style = TerminalStyle.detect(imagesRequested: options.images)
let imageBox = options.box.scaled(by: options.zoom ?? 1.0)
var report = TerminalReport(style: style, box: imageBox)

var urls: [URL]
if let base = options.changedBase {
    guard let changed = ImageSource.changed(under: options.root, base: base, repository: options.root) else {
        fail("git diff against \(base) failed — is \(options.root.path) inside a repository?")
    }
    urls = changed
    if !options.quiet { report.note("scope: files changed vs \(base)") }
} else {
    urls = ImageSource.all(under: options.root)
}
urls = ImageSource.filter(urls, include: options.include, exclude: options.exclude)

guard !urls.isEmpty else {
    if !options.quiet { report.note("no images to scan"); report.flush() }
    exit(0)
}

let approvedURL = options.approvedFile
    ?? options.root.deletingLastPathComponent().appendingPathComponent("snapshot-text-approved.yml")

var approvals = Approvals(url: approvedURL)
if FileManager.default.fileExists(atPath: approvedURL.path) {
    do {
        approvals = try Approvals.load(from: approvedURL)
    } catch {
        fail("could not read \(approvedURL.lastPathComponent): \(error)")
    }
}

if !options.quiet {
    report.note("scanning \(urls.count) image\(urls.count == 1 ? "" : "s")…")
    report.flush()
    report = TerminalReport(style: style, box: imageBox)
}

let languages = ["en-US", "fr-FR", "es-ES", "pt-BR", "de-DE", "it-IT"]
let (scanned, failures) = OCR.scanAll(urls: urls, languages: languages)

var findings: [Finding] = []
if options.checkTruncation { findings += Checks.truncated(in: scanned) }
if options.checkUntranslated {
    findings += Checks.untranslated(in: scanned, baselineLanguage: options.baselineLanguage)
}
if options.checkEdges {
    findings += Checks.edges(in: scanned, baselineLanguage: options.baselineLanguage)
}

let approvedCount = findings.count { approvals.approves($0) }
findings = findings.filter { !approvals.approves($0) }

if options.approve {
    let base = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    let added = approvals.add(findings.map {
        Approvals.entry(for: $0, reason: options.reason, relativeTo: base)
    })
    do {
        try approvals.write(to: approvedURL, header: Approvals.defaultHeader)
    } catch {
        fail("could not write \(approvedURL.path): \(error)")
    }
    print("approved \(added) finding\(added == 1 ? "" : "s") → \(approvedURL.path)")
    if added > 0 { print("edit the file to widen a glob or say why each one is acceptable") }
    exit(0)
}

let errors = findings.filter { $0.severity == .error }
let infos = findings.filter { $0.severity == .info }

for (title, group) in [("Findings", errors), ("Informational — needs a human", infos)]
    where !group.isEmpty
{
    report.heading(title)
    report.rule()
    for finding in group.sorted(by: { $0.image.url.path < $1.image.url.path }) {
        report.finding(finding, showImage: options.images)
    }
}

if !options.quiet {
    var summary = "\(scanned.count) scanned · \(errors.count) finding\(errors.count == 1 ? "" : "s")"
    if !infos.isEmpty { summary += " · \(infos.count) informational" }
    if approvedCount > 0 { summary += " · \(approvedCount) approved" }
    if !failures.isEmpty { summary += " · \(failures.count) unreadable" }
    report.heading(summary)
}

report.flush()
exit(errors.isEmpty ? 0 : 1)
