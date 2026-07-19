import AppKit
import Foundation
import Vision

/// One line of text Vision recognised, with its box in normalised coordinates (origin bottom-left).
public struct TextLine: Sendable, Hashable, Codable {
    public let text: String
    public let minX: Double
    public let minY: Double
    public let maxX: Double
    public let maxY: Double

    public init(text: String, minX: Double, minY: Double, maxX: Double, maxY: Double) {
        self.text = text
        self.minX = minX
        self.minY = minY
        self.maxX = maxX
        self.maxY = maxY
    }
}

public struct ScannedImage: Sendable {
    public let url: URL
    public let name: SnapshotName
    public let lines: [TextLine]
    public let pixelWidth: Int
    public let pixelHeight: Int
}

public enum OCR {
    /// Recognises text in one image. Language correction is **off** on purpose: it "repairs"
    /// truncated words, which is precisely the signal this tool exists to find.
    public static func scan(url: URL, languages: [String]) throws -> ScannedImage {
        guard let image = NSImage(contentsOf: url),
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
        else {
            throw AuditError.unreadableImage(url)
        }

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        request.recognitionLanguages = languages

        try VNImageRequestHandler(cgImage: cgImage, options: [:]).perform([request])

        let lines = (request.results ?? []).compactMap { observation -> TextLine? in
            guard let best = observation.topCandidates(1).first else { return nil }
            let box = observation.boundingBox
            return TextLine(
                text: best.string,
                minX: box.minX, minY: box.minY, maxX: box.maxX, maxY: box.maxY
            )
        }

        return ScannedImage(
            url: url,
            name: SnapshotName(url: url),
            lines: lines,
            pixelWidth: cgImage.width,
            pixelHeight: cgImage.height
        )
    }

    /// Scans many images concurrently, preserving input order.
    ///
    /// Concurrency is capped. Each Vision request holds a decoded bitmap, so handing the whole corpus
    /// to one task group at once exhausts memory and thrashes long before it finishes — a thousand
    /// images must run as a sliding window, not a stampede.
    ///
    /// Pass a `cache` to reuse results for images whose bytes have not changed. Hashing happens on
    /// the worker threads alongside the scans, so a cold run pays for it in parallel.
    public static func scanAll(
        urls: [URL],
        languages: [String],
        cache: OCRCache? = nil,
        maxConcurrent: Int = max(2, ProcessInfo.processInfo.activeProcessorCount - 2),
        onProgress: (@Sendable (Int, Int) -> Void)? = nil
    ) -> (scanned: [ScannedImage], failures: [URL], cached: Int) {
        let total = urls.count
        guard total > 0 else { return ([], [], 0) }

        // Vision's request handler blocks the calling thread. Dispatching it onto the cooperative
        // pool starves that pool — the pool is sized to the core count and every task sits blocked
        // inside Vision, so the work serialises and a full corpus takes minutes instead of seconds.
        // Real threads are the right tool for blocking work.
        let box = ResultBox()
        let queue = DispatchQueue(label: "ocr", attributes: .concurrent)
        let semaphore = DispatchSemaphore(value: maxConcurrent)
        let group = DispatchGroup()

        for (index, url) in urls.enumerated() {
            semaphore.wait()
            queue.async(group: group) {
                let key = cache?.key(for: url, languages: languages)

                if let cache, let key, let hit = cache.scan(for: key, url: url) {
                    box.record(
                        index: index, scanned: hit, url: url,
                        wasCached: true, total: total, onProgress: onProgress
                    )
                } else {
                    let scanned = try? OCR.scan(url: url, languages: languages)
                    if let scanned, let cache, let key { cache.store(scanned, for: key) }
                    box.record(
                        index: index, scanned: scanned, url: url,
                        wasCached: false, total: total, onProgress: onProgress
                    )
                }
                semaphore.signal()
            }
        }
        group.wait()

        return box.drain(order: urls.indices)
    }

    /// Serialises collection of results from the worker threads.
    private final class ResultBox: @unchecked Sendable {
        private let lock = NSLock()
        private var results = [Int: ScannedImage]()
        private var failures = [URL]()
        private var cached = 0
        private var done = 0

        func record(
            index: Int,
            scanned: ScannedImage?,
            url: URL,
            wasCached: Bool,
            total: Int,
            onProgress: (@Sendable (Int, Int) -> Void)?
        ) {
            lock.lock()
            done += 1
            let progress = done
            if wasCached { cached += 1 }
            if let scanned { results[index] = scanned } else { failures.append(url) }
            lock.unlock()
            onProgress?(progress, total)
        }

        func drain(order: Range<Int>) -> (scanned: [ScannedImage], failures: [URL], cached: Int) {
            lock.lock()
            defer { lock.unlock() }
            return (order.compactMap { results[$0] }, failures, cached)
        }
    }
}

public enum AuditError: Error, CustomStringConvertible {
    case unreadableImage(URL)
    case noImagesFound(String)

    public var description: String {
        switch self {
        case let .unreadableImage(url): "could not read image: \(url.path)"
        case let .noImagesFound(root): "no .png files found under \(root)"
        }
    }
}
