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
