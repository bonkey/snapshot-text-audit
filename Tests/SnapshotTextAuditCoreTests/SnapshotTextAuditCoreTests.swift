import XCTest
@testable import SnapshotTextAuditCore

final class SnapshotNameTests: XCTestCase {
    private func name(_ file: String, suite: String = "FocusWidgetSnapshotTests") -> SnapshotName {
        SnapshotName(url: URL(fileURLWithPath: "/refs/\(suite)/\(file)"))
    }

    func testParsesEverySegment() {
        let parsed = name("confirm-timed-block.148x148-small-min-default-pt-PT-light.png")
        XCTAssertEqual(parsed.suite, "FocusWidgetSnapshotTests")
        XCTAssertEqual(parsed.test, "confirm-timed-block")
        XCTAssertEqual(parsed.geometry, "148x148-small-min")
        XCTAssertEqual(parsed.trait, "default")
        XCTAssertEqual(parsed.language, "pt-PT")
        XCTAssertEqual(parsed.appearance, "light")
    }

    func testParsesNumericRegionSubtag() {
        XCTAssertEqual(name("roster.170x170-small-max-default-es-419-light.png").language, "es-419")
    }

    func testParsesBareLanguage() {
        let parsed = name("about-developer.iPhone17-default-default-en-light.png")
        XCTAssertEqual(parsed.language, "en")
        XCTAssertEqual(parsed.geometry, "iPhone17-default")
    }

    func testParsesAccessibilityTrait() {
        let parsed = name("meeting-focus.148x148-small-min-accessibility3-en-light.png")
        XCTAssertEqual(parsed.trait, "accessibility3")
        XCTAssertEqual(parsed.geometry, "148x148-small-min")
    }

    /// A name without a trait segment must not swallow part of the geometry.
    func testToleratesMissingTrait() {
        let parsed = name("lockup.sizeThatFits-en-light.png")
        XCTAssertEqual(parsed.test, "lockup")
        XCTAssertEqual(parsed.geometry, "sizeThatFits")
        XCTAssertNil(parsed.trait)
        XCTAssertEqual(parsed.language, "en")
    }

    func testVariantKeyIsSharedAcrossLanguages() {
        let en = name("roster.148x148-small-min-default-en-light.png")
        let fr = name("roster.148x148-small-min-default-fr-light.png")
        XCTAssertEqual(en.variantKey, fr.variantKey)
    }
}

final class TruncationRuleTests: XCTestCase {
    func testAcceptsWordFollowedByEllipsis() {
        XCTAssertTrue(Checks.endsTruncated("Apps desbloq..."))
        XCTAssertTrue(Checks.endsTruncated("Apps desbloq…"))
        XCTAssertTrue(Checks.endsTruncated("Bloquear durante 10…"))
    }

    /// The rule that removed 59% of raw hits: decorative menu glyphs have no word before the dots.
    func testRejectsPunctuationOnly() {
        XCTAssertFalse(Checks.endsTruncated("..."))
        XCTAssertFalse(Checks.endsTruncated("…"))
        XCTAssertFalse(Checks.endsTruncated("+..."))
        XCTAssertFalse(Checks.endsTruncated("• …"))
    }

    func testRejectsTextWithoutTrailingEllipsis() {
        XCTAssertFalse(Checks.endsTruncated("Cancelar"))
        XCTAssertFalse(Checks.endsTruncated("a... b"))
    }

    func testIgnoresSurroundingWhitespace() {
        XCTAssertTrue(Checks.endsTruncated("  Apps bloquea...  "))
    }
}

final class HostRuleTests: XCTestCase {
    func testAcceptsPlainHosts() {
        XCTAssertTrue(Checks.isHostList("instagram.com"))
        XCTAssertTrue(Checks.isHostList("googlevideo.com"))
        XCTAssertTrue(Checks.isHostList("youtu.be"))
        XCTAssertTrue(Checks.isHostList("www.instagram.com"))
        XCTAssertTrue(Checks.isHostList("r3---sn-4g5e6nzs.googlevideo.com"))
    }

    func testAcceptsHostWrappedInAURL() {
        XCTAssertTrue(Checks.isHostList("https://youtu.be/dQw4w9WgXcQ"))
        XCTAssertTrue(Checks.isHostList("instagram.com/explore"))
    }

    /// The case the rule exists for: a screen listing blocked domains.
    func testAcceptsDomainLists() {
        XCTAssertTrue(Checks.isHostList("instagram.com, youtu.be, googlevideo.com"))
        XCTAssertTrue(Checks.isHostList("instagram.com youtu.be"))
    }

    /// A sentence that merely mentions a host is still a sentence.
    func testRejectsProseAroundAHost() {
        XCTAssertFalse(Checks.isHostList("Visita instagram.com para saber mais"))
        XCTAssertFalse(Checks.isHostList("Bloquear instagram.com"))
    }

    /// The tight TLD keeps raw catalog keys visible — those are a defect, not a domain.
    func testRejectsDottedIdentifiers() {
        XCTAssertFalse(Checks.isHostList("settings.notifications"))
        XCTAssertFalse(Checks.isHostList("Bloqueado.Apps"))
        XCTAssertFalse(Checks.isHostList("Terminar. Continuar."))
    }

    func testRejectsTextWithoutALabelPair() {
        XCTAssertFalse(Checks.isHostList("Cancelar"))
        XCTAssertFalse(Checks.isHostList(""))
        XCTAssertFalse(Checks.isHostList("instagram."))
        XCTAssertFalse(Checks.isHostList(".com"))
    }
}

final class UntranslatedRuleTests: XCTestCase {
    private func image(_ language: String, _ texts: [String]) -> ScannedImage {
        let url = URL(fileURLWithPath: "/refs/Suite/roster.148x148-small-min-default-\(language)-light.png")
        return ScannedImage(
            url: url,
            name: SnapshotName(url: url),
            lines: texts.map { TextLine(text: $0, minX: 0.2, minY: 0.2, maxX: 0.8, maxY: 0.8) },
            pixelWidth: 148,
            pixelHeight: 148
        )
    }

    private func findings(_ texts: [String]) -> [Finding] {
        Checks.untranslated(in: [image("en", texts), image("pt-PT", texts)], baselineLanguage: "en")
    }

    func testReportsIdenticalSentences() {
        XCTAssertEqual(findings(["Block distracting apps"]).count, 1)
    }

    func testSkipsHosts() {
        XCTAssertTrue(findings(["googlevideo.com"]).isEmpty)
        XCTAssertTrue(findings(["instagram.com, youtu.be"]).isEmpty)
    }

    /// Skipping hosts must not spill over onto the sentence next to them.
    func testStillReportsSentencesOnAScreenOfHosts() {
        let mixed = findings(["instagram.com", "Blocked while you focus"])
        XCTAssertEqual(mixed.count, 1)
        XCTAssertEqual(mixed.first?.line.text, "Blocked while you focus")
    }
}

final class ImageBoxTests: XCTestCase {
    func testDefaultFitsTallScreensWithoutFloodingScrollback() {
        let box = TerminalReport.ImageBox()
        XCTAssertEqual(box.width, 400)
        XCTAssertEqual(box.height, 700)
    }

    func testZoomScalesBothDimensions() {
        let doubled = TerminalReport.ImageBox().scaled(by: 2)
        XCTAssertEqual(doubled.width, 800)
        XCTAssertEqual(doubled.height, 1400)

        let tripled = TerminalReport.ImageBox().scaled(by: 3)
        XCTAssertEqual(tripled.width, 1200)
        XCTAssertEqual(tripled.height, 2100)
    }

    func testFractionalZoomRounds() {
        let half = TerminalReport.ImageBox(width: 401, height: 701).scaled(by: 0.5)
        XCTAssertEqual(half.width, 201)
        XCTAssertEqual(half.height, 351)
    }

    /// The terminal reserves the height it is told and scales inside it, so a box-shaped
    /// reservation leaves dead rows under a wide image. Fitted output must match the image's shape.
    func testFittedMatchesImageAspectRatio() {
        let box = TerminalReport.ImageBox(width: 800, height: 1400)
        let wide = box.fitted(intrinsicWidth: 390, intrinsicHeight: 220)
        XCTAssertEqual(wide.width, 800)
        XCTAssertEqual(wide.height, 451)
        XCTAssertLessThan(wide.height, box.height)
    }

    func testFittedClampsTallImagesByHeight() {
        let box = TerminalReport.ImageBox(width: 800, height: 1400)
        let tall = box.fitted(intrinsicWidth: 1206, intrinsicHeight: 2622)
        XCTAssertEqual(tall.height, 1400)
        XCTAssertEqual(tall.width, 644)
        XCTAssertLessThan(tall.width, box.width)
    }

    func testFittedScalesSquareToBothLimits() {
        let box = TerminalReport.ImageBox(width: 400, height: 700)
        let square = box.fitted(intrinsicWidth: 444, intrinsicHeight: 444)
        XCTAssertEqual(square.width, 400)
        XCTAssertEqual(square.height, 400)
    }

    func testFittedFallsBackWhenIntrinsicSizeUnknown() {
        let box = TerminalReport.ImageBox(width: 400, height: 700)
        let unknown = box.fitted(intrinsicWidth: 0, intrinsicHeight: 0)
        XCTAssertEqual(unknown.width, 400)
        XCTAssertEqual(unknown.height, 700)
    }

    func testTinyZoomStaysVisible() {
        let tiny = TerminalReport.ImageBox().scaled(by: 0.001)
        XCTAssertGreaterThanOrEqual(tiny.width, 32)
        XCTAssertGreaterThanOrEqual(tiny.height, 32)
    }
}

final class ApprovalPathMatchingTests: XCTestCase {
    private let path = "ios/App/Snapshots/CalendarWidgetSnapshotTests/meeting-focus.170x170-en-light.png"

    private func matches(_ pattern: String) -> Bool {
        Approvals.Entry.matchesPath(pattern: pattern, path: path)
    }

    func testBareFileName() {
        XCTAssertTrue(matches("meeting-focus.170x170-en-light.png"))
    }

    func testFileNameGlob() {
        XCTAssertTrue(matches("meeting-focus*"))
    }

    func testPathSuffix() {
        XCTAssertTrue(matches("CalendarWidgetSnapshotTests/meeting-focus.170x170-en-light.png"))
    }

    func testDirectoryGlob() {
        XCTAssertTrue(matches("CalendarWidgetSnapshotTests/*"))
        XCTAssertTrue(matches("*/meeting-focus*"))
    }

    func testFullPath() {
        XCTAssertTrue(matches(path))
    }

    func testLeadingDoubleStar() {
        XCTAssertTrue(matches("**/CalendarWidgetSnapshotTests/*"))
    }

    func testGlobSpansDirectories() {
        XCTAssertTrue(matches("App/*/meeting-focus*"))
    }

    func testNonMatchingPatternIsRejected() {
        XCTAssertFalse(matches("FocusWidgetSnapshotTests/*"))
        XCTAssertFalse(matches("roster*"))
    }
}

final class ApprovalsTests: XCTestCase {
    private func entry(file: String, text: String, kind: String? = nil) -> Approvals.Entry {
        Approvals.Entry(file: file, text: text, reason: "because", kind: kind)
    }

    private let yaml = """
    approved:
      - file: CalendarWidgetSnapshotTests/meeting-focus*
        text: "*"
        reason: titles ellipsise by design
        kind: truncated
    """

    func testRoundTripsThroughYAML() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("approvals-\(UUID().uuidString).yml")
        var approvals = Approvals(entries: [entry(file: "a/b.png", text: "Cut...")])
        try approvals.write(to: url)
        let reloaded = try Approvals.load(from: url)
        XCTAssertEqual(reloaded.entries, approvals.entries)
        try? FileManager.default.removeItem(at: url)
    }

    func testEmptyFileLoadsAsEmpty() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("empty-\(UUID().uuidString).yml")
        try "".write(to: url, atomically: true, encoding: .utf8)
        XCTAssertEqual(try Approvals.load(from: url).count, 0)
        try? FileManager.default.removeItem(at: url)
    }

    func testParsesHandWrittenYAML() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("hand-\(UUID().uuidString).yml")
        try yaml.write(to: url, atomically: true, encoding: .utf8)
        let approvals = try Approvals.load(from: url)
        XCTAssertEqual(approvals.count, 1)
        XCTAssertEqual(approvals.entries.first?.kind, "truncated")
        try? FileManager.default.removeItem(at: url)
    }

    /// Re-running --approve must not pile up duplicates of what a glob already covers.
    func testAddSkipsWhatIsAlreadyCovered() {
        var approvals = Approvals(entries: [entry(file: "CalendarWidget*/*", text: "*", kind: "truncated")])
        let added = approvals.add([
            entry(file: "CalendarWidgetSnapshotTests/meeting-focus.png", text: "Micro...", kind: "truncated"),
        ])
        XCTAssertEqual(added, 0)
        XCTAssertEqual(approvals.count, 1)
    }

    func testAddAppendsGenuinelyNewEntries() {
        var approvals = Approvals(entries: [entry(file: "a/b.png", text: "One...", kind: "truncated")])
        let added = approvals.add([entry(file: "a/c.png", text: "Two...", kind: "truncated")])
        XCTAssertEqual(added, 1)
        XCTAssertEqual(approvals.count, 2)
    }

    /// A kind on the entry confines it: approving a truncation must not also accept a bad translation.
    func testKindConfinesTheApproval() {
        let approvals = Approvals(entries: [entry(file: "a/b.png", text: "*", kind: "truncated")])
        XCTAssertTrue(approvals.entries[0].matches(file: "a/b.png", text: "x...", kind: "truncated"))
        XCTAssertFalse(approvals.entries[0].matches(file: "a/b.png", text: "x...", kind: "untranslated"))
    }

    func testOmittedKindCoversEveryKind() {
        let approvals = Approvals(entries: [entry(file: "a/b.png", text: "*")])
        XCTAssertTrue(approvals.entries[0].matches(file: "a/b.png", text: "x", kind: "truncated"))
        XCTAssertTrue(approvals.entries[0].matches(file: "a/b.png", text: "x", kind: "untranslated"))
    }

    func testDefaultFileNameIsADotfile() {
        XCTAssertEqual(Approvals.defaultFileName, ".snapshot-text-approved.yml")
        XCTAssertTrue(Approvals.defaultFileName.hasPrefix("."))
    }

    func testGeneratedPathIsRelativeToBase() {
        let base = URL(fileURLWithPath: "/repo/ios")
        let file = URL(fileURLWithPath: "/repo/ios/App/Snapshots/Suite/a.png")
        XCTAssertEqual(Approvals.path(for: file, relativeTo: base), "App/Snapshots/Suite/a.png")
    }

    func testGeneratedPathFallsBackToAbsoluteOutsideBase() {
        let base = URL(fileURLWithPath: "/repo/ios")
        let file = URL(fileURLWithPath: "/elsewhere/a.png")
        XCTAssertEqual(Approvals.path(for: file, relativeTo: base), "/elsewhere/a.png")
    }
}

final class OCRCacheTests: XCTestCase {
    private var directory = URL(fileURLWithPath: "/")
    private let languages = ["en-US", "pt-BR"]

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("cache-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func cache() -> OCRCache { OCRCache(directory: directory) }

    private func image(_ name: String, contents: String) throws -> URL {
        let url = directory.appendingPathComponent(name)
        try contents.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private func scanned(_ url: URL, _ texts: [String]) -> ScannedImage {
        ScannedImage(
            url: url,
            name: SnapshotName(url: url),
            lines: texts.map { TextLine(text: $0, minX: 0.1, minY: 0.2, maxX: 0.3, maxY: 0.4) },
            pixelWidth: 148,
            pixelHeight: 148
        )
    }

    func testRoundTripsAScan() throws {
        let url = try image("roster.148x148-en-light.png", contents: "pixels")
        let key = try XCTUnwrap(cache().key(for: url, languages: languages))

        cache().store(scanned(url, ["Block distracting apps"]), for: key)
        let hit = try XCTUnwrap(cache().scan(for: key, url: url))

        XCTAssertEqual(hit.lines.map(\.text), ["Block distracting apps"])
        XCTAssertEqual(hit.pixelWidth, 148)
        XCTAssertEqual(hit.lines.first?.maxY, 0.4)
    }

    func testMissReturnsNil() throws {
        let url = try image("roster.148x148-en-light.png", contents: "pixels")
        let key = try XCTUnwrap(cache().key(for: url, languages: languages))
        XCTAssertNil(cache().scan(for: key, url: url))
    }

    /// The point of keying on content: a rewritten file with the same pixels still hits.
    func testKeyIgnoresPathAndModificationDate() throws {
        let first = try image("roster.148x148-en-light.png", contents: "pixels")
        let second = try image("meeting.170x170-pt-PT-dark.png", contents: "pixels")
        XCTAssertEqual(
            cache().key(for: first, languages: languages),
            cache().key(for: second, languages: languages)
        )
    }

    func testChangedPixelsAreADifferentKey() throws {
        let before = try image("a.png", contents: "pixels")
        let after = try image("b.png", contents: "different pixels")
        XCTAssertNotEqual(
            cache().key(for: before, languages: languages),
            cache().key(for: after, languages: languages)
        )
    }

    /// Recognition languages change what Vision returns, so they must not share an entry.
    func testLanguagesArePartOfTheKey() throws {
        let url = try image("a.png", contents: "pixels")
        XCTAssertNotEqual(
            cache().key(for: url, languages: ["en-US"]),
            cache().key(for: url, languages: ["en-US", "de-DE"])
        )
    }

    func testUnreadableFileHasNoKey() {
        XCTAssertNil(cache().key(for: directory.appendingPathComponent("gone.png"), languages: languages))
    }

    /// A byte-identical render in another language shares an entry, but must keep its own identity.
    func testHitCarriesTheRequestingFilesName() throws {
        let english = try image("roster.148x148-small-min-default-en-light.png", contents: "pixels")
        let portuguese = try image("roster.148x148-small-min-default-pt-PT-light.png", contents: "pixels")
        let key = try XCTUnwrap(cache().key(for: english, languages: languages))

        cache().store(scanned(english, ["Focus"]), for: key)
        let hit = try XCTUnwrap(cache().scan(for: key, url: portuguese))

        XCTAssertEqual(hit.url, portuguese)
        XCTAssertEqual(hit.name.language, "pt-PT")
    }

    func testStoreOnAnUnwritableDirectoryIsSurvivable() throws {
        let url = try image("a.png", contents: "pixels")
        let blocked = OCRCache(directory: URL(fileURLWithPath: "/dev/null/nope"))
        let key = try XCTUnwrap(blocked.key(for: url, languages: languages))
        blocked.store(scanned(url, ["Focus"]), for: key)
        XCTAssertNil(blocked.scan(for: key, url: url))
    }

    func testDefaultDirectoryIsUnderCaches() {
        let path = OCRCache.defaultDirectory.path
        XCTAssertTrue(path.hasSuffix("/snapshot-text-audit"))
        XCTAssertTrue(path.contains("Caches"))
    }
}

final class GlobFilterTests: XCTestCase {
    private let urls = [
        URL(fileURLWithPath: "/refs/FocusWidgetSnapshotTests/confirm-timed-block.148x148-en-light.png"),
        URL(fileURLWithPath: "/refs/FocusWidgetSnapshotTests/roster.148x148-en-dark.png"),
        URL(fileURLWithPath: "/refs/CalendarWidgetSnapshotTests/meeting-focus.148x148-en-light.png"),
    ]

    func testIncludeNarrows() {
        let filtered = ImageSource.filter(urls, include: ["confirm-*"], exclude: [])
        XCTAssertEqual(filtered.count, 1)
    }

    func testExcludeRemoves() {
        let filtered = ImageSource.filter(urls, include: [], exclude: ["*-dark.png"])
        XCTAssertEqual(filtered.count, 2)
    }

    func testSuitePrefixMatches() {
        let filtered = ImageSource.filter(urls, include: ["CalendarWidgetSnapshotTests/*"], exclude: [])
        XCTAssertEqual(filtered.count, 1)
    }

    func testExcludeWinsOverInclude() {
        let filtered = ImageSource.filter(urls, include: ["*"], exclude: ["*-dark.png"])
        XCTAssertEqual(filtered.count, 2)
    }
}

final class MarkdownReportTests: XCTestCase {
    private func finding(
        _ text: String,
        file: String = "roster.148x148-default-pt-PT-light.png",
        suite: String = "Suite"
    ) -> Finding {
        let url = URL(fileURLWithPath: "/repo/Snapshots/\(suite)/\(file)")
        let image = ScannedImage(
            url: url,
            name: SnapshotName(url: url),
            lines: [TextLine(text: text, minX: 0.2, minY: 0.2, maxX: 0.8, maxY: 0.8)],
            pixelWidth: 148,
            pixelHeight: 148
        )
        return .truncated(image: image, line: image.lines[0])
    }

    private func render(
        _ findings: [Finding],
        to path: String = "/repo/audit.md",
        root: String = "/repo/Snapshots"
    ) -> String {
        MarkdownReport(destination: URL(fileURLWithPath: path), root: URL(fileURLWithPath: root))
            .render(findings: findings, summary: "2 scanned · 1 finding")
    }

    /// Links must resolve from the report, not from wherever the scan was run.
    func testLinksAreRelativeToTheReport() {
        let markdown = render([finding("Apps desbloq…")])
        XCTAssertTrue(markdown.contains("(Snapshots/Suite/roster.148x148-default-pt-PT-light.png)"))
        XCTAssertFalse(markdown.contains("/repo/Snapshots"))
    }

    func testWalksUpWhenTheReportSitsOutsideTheCorpus() {
        let markdown = render([finding("Apps desbloq…")], to: "/repo/build/reports/audit.md")
        XCTAssertTrue(markdown.contains("(../../Snapshots/Suite/roster.148x148-default-pt-PT-light.png)"))
    }

    func testGroupsByFolderWithATableOfContents() {
        let markdown = render([
            finding("Apps desbloq…", suite: "WidgetTests"),
            finding("Bloquear durante 10…", file: "confirm.148x148-default-fr-light.png", suite: "AppTests"),
        ])
        XCTAssertTrue(markdown.contains("## Contents"))
        XCTAssertTrue(markdown.contains("[AppTests](#apptests)"))
        XCTAssertTrue(markdown.contains("[WidgetTests](#widgettests)"))
        XCTAssertTrue(markdown.contains("\n## AppTests\n"))
    }

    /// Headings name the corpus, so a report filed in a build directory still reads as suites
    /// rather than as a run of `..`.
    func testHeadingsAreNamedRelativeToTheScannedRoot() {
        let markdown = render(
            [finding("Apps desbloq…", suite: "WidgetTests")],
            to: "/repo/build/reports/audit.md"
        )
        XCTAssertTrue(markdown.contains("\n## WidgetTests\n"))
        XCTAssertTrue(markdown.contains("(../../Snapshots/WidgetTests/roster.148x148-default-pt-PT-light.png)"))
    }

    func testEachFindingFoldsAndInlinesItsImage() {
        let markdown = render([finding("Apps desbloq…")])
        XCTAssertTrue(markdown.contains("<details>"))
        XCTAssertTrue(markdown.contains("<code>TRUNCATED</code> `pt-PT`"))
        XCTAssertTrue(markdown.contains("[![roster"))
    }

    /// Recognised copy is arbitrary text, and none of it should be read as markup.
    func testEscapesRecognisedText() {
        let markdown = render([finding("*Wi-Fi* <off> [1]…")])
        XCTAssertTrue(markdown.contains("\\*Wi-Fi\\* &lt;off&gt; \\[1\\]…"))
    }

    func testEncodesSpacesInPaths() {
        let markdown = render([finding("Apps desbloq…", file: "focus mode.png")])
        XCTAssertTrue(markdown.contains("focus%20mode.png"))
    }

    func testSaysSoWhenThereIsNothingToReport() {
        XCTAssertTrue(render([]).contains("Nothing to report."))
    }
}
