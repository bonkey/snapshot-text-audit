import Foundation

public enum Severity: String, Sendable, CaseIterable {
    /// Reliable enough to fail a build.
    case error
    /// Real but needs a human to confirm — never fails a build.
    case info
}

public enum Finding: Sendable {
    case truncated(image: ScannedImage, line: TextLine)
    case untranslated(image: ScannedImage, line: TextLine, baselineLanguage: String)
    case edge(image: ScannedImage, line: TextLine, side: Side)

    public enum Side: String, Sendable { case leading, trailing, top, bottom }

    public var image: ScannedImage {
        switch self {
        case let .truncated(image, _), let .untranslated(image, _, _), let .edge(image, _, _): image
        }
    }

    public var line: TextLine {
        switch self {
        case let .truncated(_, line), let .untranslated(_, line, _), let .edge(_, line, _): line
        }
    }

    public var severity: Severity {
        switch self {
        case .truncated, .untranslated: .error
        case .edge: .info
        }
    }

    public var kind: String {
        switch self {
        case .truncated: "truncated"
        case .untranslated: "untranslated"
        case .edge: "edge"
        }
    }

    public var headline: String {
        switch self {
        case let .truncated(_, line):
            "text truncated — \(line.text.trimmed())"
        case let .untranslated(_, line, base):
            "identical to \(base) — likely untranslated: \(line.text.trimmed())"
        case let .edge(_, line, side):
            "text reaches the \(side.rawValue) edge — \(line.text.trimmed())"
        }
    }

}

public enum Checks {
    /// Text cut short with an ellipsis.
    ///
    /// A letter or digit must sit immediately before the dots. Without that rule the dominant hit is
    /// a decorative `···` overflow-menu glyph — in the corpus this was built against, that single
    /// condition removed 59% of raw hits with no judgement call.
    public static func truncated(in images: [ScannedImage]) -> [Finding] {
        images.flatMap { image in
            image.lines.compactMap { line in
                guard endsTruncated(line.text) else { return nil }
                return .truncated(image: image, line: line)
            }
        }
    }

    static func endsTruncated(_ text: String) -> Bool {
        let trimmed = text.trimmed()
        guard trimmed.hasSuffix("…") || trimmed.hasSuffix("...") else { return false }
        let head = trimmed.hasSuffix("…")
            ? String(trimmed.dropLast())
            : String(trimmed.dropLast(3))
        guard let last = head.last else { return false }
        return last.isLetter || last.isNumber
    }

    /// Strings that render identically in a translated language and in the baseline language.
    ///
    /// A missing catalog key is invisible to catalog tooling — the key exists, the wrong text ships.
    /// Short and non-alphabetic strings are skipped: numerals, times and product names are expected
    /// to match across languages.
    public static func untranslated(
        in images: [ScannedImage],
        baselineLanguage: String,
        minimumLength: Int = 12
    ) -> [Finding] {
        var baselineByVariant = [String: Set<String>]()
        for image in images where image.name.language == baselineLanguage {
            baselineByVariant[image.name.variantKey, default: []]
                .formUnion(image.lines.map { $0.text.trimmed() })
        }

        var findings = [Finding]()
        for image in images {
            guard let language = image.name.language, language != baselineLanguage,
                  let baseline = baselineByVariant[image.name.variantKey]
            else { continue }

            for line in image.lines {
                let text = line.text.trimmed()
                guard text.count >= minimumLength,
                      text.contains(where: { $0.isLetter }),
                      baseline.contains(text)
                else { continue }
                findings.append(.untranslated(image: image, line: line, baselineLanguage: baselineLanguage))
            }
        }
        return findings
    }

    /// Text running into a frame edge, which *may* mean it is sliced.
    ///
    /// Informational only. A bounding box near an edge cannot be told apart from text that simply
    /// ends there, so this is wrong far more often than it is right; measured against the corpus this
    /// was built for, roughly nine in ten hits were harmless.
    ///
    /// One filter is applied because it was verified to help: a cut that appears in *every* language
    /// of a render is structural — a scroll fold or a pinned footer — while a real overflow spares the
    /// baseline language. Groups that fire in every available language are dropped.
    public static func edges(
        in images: [ScannedImage],
        baselineLanguage: String,
        margin: Double = 0.015
    ) -> [Finding] {
        var candidates = [Finding]()
        for image in images {
            for line in image.lines {
                if line.maxX >= 1 - margin { candidates.append(.edge(image: image, line: line, side: .trailing)) }
                if line.minX <= margin { candidates.append(.edge(image: image, line: line, side: .leading)) }
                if line.maxY >= 1 - margin { candidates.append(.edge(image: image, line: line, side: .top)) }
                if line.minY <= margin { candidates.append(.edge(image: image, line: line, side: .bottom)) }
            }
        }

        let languagesPerVariant = Dictionary(grouping: images, by: { $0.name.variantKey })
            .mapValues { Set($0.compactMap(\.name.language)) }

        var hitLanguages = [String: Set<String>]()
        for finding in candidates {
            guard let language = finding.image.name.language else { continue }
            hitLanguages[groupKey(finding), default: []].insert(language)
        }

        return candidates.filter { finding in
            let available = languagesPerVariant[finding.image.name.variantKey] ?? []
            guard available.count > 1, available.contains(baselineLanguage) else { return true }
            let hit = hitLanguages[groupKey(finding)] ?? []
            return hit != available
        }
    }

    private static func groupKey(_ finding: Finding) -> String {
        guard case let .edge(image, _, side) = finding else { return "" }
        return "\(image.name.variantKey)|\(side.rawValue)"
    }
}

extension String {
    func trimmed() -> String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
