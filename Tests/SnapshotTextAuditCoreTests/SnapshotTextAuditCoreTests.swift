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

    func testTinyZoomStaysVisible() {
        let tiny = TerminalReport.ImageBox().scaled(by: 0.001)
        XCTAssertGreaterThanOrEqual(tiny.width, 32)
        XCTAssertGreaterThanOrEqual(tiny.height, 32)
    }
}

final class BaselineTests: XCTestCase {
    private let record = """
    FocusWidgetSnapshotTests | confirm-timed-block | * | * | truncated | Bloq... | by design
    """

    private func key(
        test: String = "confirm-timed-block",
        geometry: String = "148x148-small-min",
        language: String = "pt-PT",
        text: String = "Bloq..."
    ) -> BaselineKey {
        BaselineKey(
            suite: "FocusWidgetSnapshotTests", test: test, geometry: geometry,
            language: language, kind: "truncated", text: text
        )
    }

    func testWildcardsMatchEveryVariant() {
        let baseline = Baseline(entries: [record])
        XCTAssertTrue(baseline.excludes(key()))
        XCTAssertTrue(baseline.excludes(key(language: "es")))
        XCTAssertTrue(baseline.excludes(key(geometry: "158x158-small-mid")))
    }

    /// The point of the design: renaming a file must not resurrect accepted findings.
    func testSurvivesFileRenames() {
        let baseline = Baseline(entries: [record])
        // Same render, file renamed to carry a Dynamic Type segment — geometry is wildcarded.
        XCTAssertTrue(baseline.excludes(key(geometry: "148x148-small-min-accessibility3")))
    }

    /// The other half: changed copy is a new finding and must come back for review.
    func testChangedTextIsNotExcluded() {
        let baseline = Baseline(entries: [record])
        XCTAssertFalse(baseline.excludes(key(text: "Bloquear...")))
    }

    func testDifferentTestIsNotExcluded() {
        let baseline = Baseline(entries: [record])
        XCTAssertFalse(baseline.excludes(key(test: "confirm-until-event")))
    }

    func testIgnoresCommentsAndBlankLines() {
        let baseline = Baseline(entries: ["# a comment", "", "   ", record])
        XCTAssertEqual(baseline.count, 1)
    }

    func testRejectsMalformedRecords() {
        XCTAssertEqual(Baseline(entries: ["too | few | fields"]).count, 0)
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
