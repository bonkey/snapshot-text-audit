import CryptoKit
import Foundation

/// Vision results, kept between runs and keyed by image content.
///
/// OCR is the whole cost of a run — everything after it is string comparison. Re-scanning a corpus
/// that has not changed is the ordinary case, not the exception: widening an approval, toggling
/// `--edges`, or narrowing to `--include` all re-read the same pixels to reach a different answer,
/// and on a large corpus that is minutes each time.
///
/// The key is the image's bytes. Not its path, and not its modification date — `git checkout`
/// rewrites mtimes without changing a pixel, and snapshot references get regenerated wholesale, so
/// a date-keyed cache would miss almost every time it mattered. Hashing the file costs a read where
/// a miss costs a Vision pass, so the trade is lopsided in the cache's favour even when it misses.
///
/// Keying on content also means an entry cannot go stale: a changed PNG is a different key, never a
/// wrong hit. Two renders that are byte-identical share one entry, which is correct — identical
/// pixels recognise identically — and the reconstructed ``ScannedImage`` still carries each file's
/// own path and parsed name.
public struct OCRCache: Sendable {
    /// Bump when a change to `OCR.scan` would make stored entries wrong. Old entries then miss and
    /// are rewritten, rather than being silently believed.
    private static let formatVersion = 1

    public let directory: URL

    public init(directory: URL = OCRCache.defaultDirectory) {
        self.directory = directory
    }

    /// `~/Library/Caches/snapshot-text-audit` — nothing lands in the repository, and the OS is free
    /// to purge it under disk pressure, which is the correct fate for a pure derivation.
    public static var defaultDirectory: URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return base.appendingPathComponent("snapshot-text-audit", isDirectory: true)
    }

    /// What Vision produced, and nothing that can be recovered from the path.
    ///
    /// `url` and `name` are deliberately absent: they are derived from wherever the file sits now,
    /// so storing them would let one render's name be served for another with the same pixels.
    private struct Entry: Codable {
        let lines: [TextLine]
        let pixelWidth: Int
        let pixelHeight: Int
    }

    /// Content hash of the image, salted with everything that changes what a scan would return.
    ///
    /// Returns nil for an unreadable file — the caller falls through to a real scan, which produces
    /// the proper error.
    public func key(for url: URL, languages: [String]) -> String? {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return nil }
        var hash = SHA256()
        hash.update(data: data)
        hash.update(data: Data("v\(Self.formatVersion)|\(languages.joined(separator: ","))".utf8))
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// The stored scan for `key`, re-attached to the file being scanned now.
    public func scan(for key: String, url: URL) -> ScannedImage? {
        guard let data = try? Data(contentsOf: file(for: key)),
              let entry = try? JSONDecoder().decode(Entry.self, from: data)
        else { return nil }

        return ScannedImage(
            url: url,
            name: SnapshotName(url: url),
            lines: entry.lines,
            pixelWidth: entry.pixelWidth,
            pixelHeight: entry.pixelHeight
        )
    }

    /// Records a scan. Failures are swallowed on purpose — a cache that cannot be written is a
    /// slower run, not a broken one, and an unwritable cache directory must never fail an audit.
    public func store(_ scanned: ScannedImage, for key: String) {
        let entry = Entry(
            lines: scanned.lines,
            pixelWidth: scanned.pixelWidth,
            pixelHeight: scanned.pixelHeight
        )
        guard let data = try? JSONEncoder().encode(entry) else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? data.write(to: file(for: key), options: .atomic)
    }

    private func file(for key: String) -> URL {
        directory.appendingPathComponent("\(key).json")
    }
}
