import Foundation

/// The identity of a snapshot reference, parsed out of its file name.
///
/// Keying findings on these fields rather than on the file name is what makes a baseline survive a
/// mass rename: inserting a trait segment or renaming a test changes the path but not the rendered
/// pixels, and a finding that did not change should not resurface as new.
public struct SnapshotName: Sendable, Hashable {
    public let suite: String
    public let test: String
    public let geometry: String
    public let trait: String?
    public let language: String?
    public let appearance: String?
    public let fileName: String

    /// Known `DynamicTypeSize` case names, plus the explicit `default` marker.
    static let traits: Set<String> = [
        "default", "xSmall", "small", "medium", "large", "xLarge", "xxLarge", "xxxLarge",
        "accessibility1", "accessibility2", "accessibility3", "accessibility4", "accessibility5",
    ]

    static let appearances: Set<String> = ["light", "dark"]

    public init(url: URL) {
        let file = url.lastPathComponent
        fileName = file
        suite = url.deletingLastPathComponent().lastPathComponent

        var body = file
        if body.hasSuffix(".png") { body.removeLast(4) }

        // `<test>.<geometry>-<trait>-<language>-<appearance>`; everything after the first dot is
        // hyphen-separated, so peel known segments off the tail and treat the remainder as geometry.
        guard let dot = body.firstIndex(of: ".") else {
            test = body
            geometry = ""
            trait = nil
            language = nil
            appearance = nil
            return
        }
        test = String(body[body.startIndex ..< dot])
        var parts = body[body.index(after: dot)...].split(separator: "-").map(String.init)

        var appearanceValue: String?
        if let last = parts.last, Self.appearances.contains(last) {
            appearanceValue = parts.removeLast()
        }
        appearance = appearanceValue

        language = Self.popLanguage(&parts)

        var traitValue: String?
        if let last = parts.last, Self.traits.contains(last) {
            traitValue = parts.removeLast()
        }
        trait = traitValue

        geometry = parts.joined(separator: "-")
    }

    /// Pops a trailing BCP-47-ish tag: `en`, `fr`, `pt-BR`, `es-419`.
    private static func popLanguage(_ parts: inout [String]) -> String? {
        guard let last = parts.last else { return nil }

        let isRegion = last.count == 2 && last.allSatisfy(\.isUppercase)
        let isNumericRegion = last.count == 3 && last.allSatisfy(\.isNumber)
        if isRegion || isNumericRegion, parts.count >= 2 {
            let candidate = parts[parts.count - 2]
            if candidate.count == 2, candidate.allSatisfy({ $0.isLowercase && $0.isLetter }) {
                parts.removeLast(2)
                return "\(candidate)-\(last)"
            }
        }
        if last.count == 2, last.allSatisfy({ $0.isLowercase && $0.isLetter }) {
            return parts.removeLast()
        }
        return nil
    }

    /// Identity shared by every language variant of the same render — the grouping used to tell a
    /// locale-driven overflow apart from a cut that happens in every language.
    public var variantKey: String {
        "\(suite)|\(test)|\(geometry)|\(trait ?? "-")|\(appearance ?? "-")"
    }
}
