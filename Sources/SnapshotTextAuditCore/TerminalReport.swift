import Foundation

public struct TerminalStyle: Sendable {
    public let colour: Bool
    public let hyperlinks: Bool
    public let inlineImages: Bool

    public init(colour: Bool, hyperlinks: Bool, inlineImages: Bool) {
        self.colour = colour
        self.hyperlinks = hyperlinks
        self.inlineImages = inlineImages
    }

    /// Detects capabilities. Everything degrades to plain text when stdout is not a terminal, so
    /// piping to a file or a CI log never emits escape sequences or base64 image payloads.
    public static func detect(imagesRequested: Bool) -> TerminalStyle {
        let isTTY = isatty(STDOUT_FILENO) == 1
        guard isTTY else { return TerminalStyle(colour: false, hyperlinks: false, inlineImages: false) }

        let env = ProcessInfo.processInfo.environment
        if env["NO_COLOR"] != nil {
            return TerminalStyle(colour: false, hyperlinks: false, inlineImages: false)
        }

        let isITerm = env["TERM_PROGRAM"] == "iTerm.app" || env["LC_TERMINAL"] == "iTerm2"
        // tmux and screen swallow the image protocol unless explicitly configured for passthrough.
        let multiplexed = env["TMUX"] != nil || (env["TERM"]?.hasPrefix("screen") ?? false)

        return TerminalStyle(
            colour: true,
            hyperlinks: true,
            inlineImages: imagesRequested && isITerm && !multiplexed
        )
    }
}

public struct TerminalReport {
    private let style: TerminalStyle
    private let box: ImageBox
    private var out = ""

    /// The largest area an inline image may occupy, in pixels.
    ///
    /// A width cap alone would be wrong here: snapshot corpora mix near-square widget tiles with
    /// phone screens three times taller than they are wide, and sizing those by width alone buries
    /// the terminal in scrollback. Images are scaled down to fit both dimensions, never stretched.
    public struct ImageBox: Sendable {
        public var width: Int
        public var height: Int

        public init(width: Int = 400, height: Int = 700) {
            self.width = width
            self.height = height
        }

        public func scaled(by zoom: Double) -> ImageBox {
            ImageBox(
                width: max(32, Int((Double(width) * zoom).rounded())),
                height: max(32, Int((Double(height) * zoom).rounded()))
            )
        }

        /// The exact size an image of `intrinsic` dimensions should be drawn at to fit this box.
        ///
        /// The terminal reserves whatever height it is given and only *then* scales the image inside
        /// it, so handing it the box height leaves a band of empty rows under anything that is not
        /// exactly the box's aspect ratio. Computing the fitted size here keeps the reservation and
        /// the drawing the same shape.
        public func fitted(intrinsicWidth: Int, intrinsicHeight: Int) -> (width: Int, height: Int) {
            guard intrinsicWidth > 0, intrinsicHeight > 0 else { return (width, height) }
            let scale = min(Double(width) / Double(intrinsicWidth), Double(height) / Double(intrinsicHeight))
            return (
                max(1, Int((Double(intrinsicWidth) * scale).rounded())),
                max(1, Int((Double(intrinsicHeight) * scale).rounded()))
            )
        }
    }

    public init(style: TerminalStyle, box: ImageBox = ImageBox()) {
        self.style = style
        self.box = box
    }

    private static let esc = "\u{1B}"
    private static let bel = "\u{07}"
    private static let st = "\u{1B}\\"

    private func paint(_ text: String, _ code: String) -> String {
        style.colour ? "\(Self.esc)[\(code)m\(text)\(Self.esc)[0m" : text
    }

    private func link(_ text: String, to url: URL) -> String {
        guard style.hyperlinks else { return text }
        return "\(Self.esc)]8;;\(url.absoluteString)\(Self.st)\(text)\(Self.esc)]8;;\(Self.st)"
    }

    /// iTerm2 inline image protocol. Returns nil when unsupported or the file cannot be read.
    private func image(_ url: URL, intrinsicWidth: Int, intrinsicHeight: Int) -> String? {
        guard style.inlineImages, let data = try? Data(contentsOf: url) else { return nil }
        let name = Data(url.lastPathComponent.utf8).base64EncodedString()
        let payload = data.base64EncodedString()
        let size = box.fitted(intrinsicWidth: intrinsicWidth, intrinsicHeight: intrinsicHeight)
        return "\(Self.esc)]1337;File=name=\(name);size=\(data.count);inline=1;"
            + "width=\(size.width)px;height=\(size.height)px;preserveAspectRatio=1:\(payload)\(Self.bel)"
    }

    public mutating func heading(_ text: String) {
        out += "\n" + paint(text, "1") + "\n"
    }

    public mutating func note(_ text: String) {
        out += paint(text, "2") + "\n"
    }

    public mutating func finding(_ finding: Finding, showImage: Bool) {
        // Severity picks the colour, the kind picks the word: truncated and untranslated are both
        // errors, so keying the text off severity alone badges a bad translation as a truncation.
        let badge = switch finding.severity {
        case .error: paint(" \(finding.kind.uppercased()) ", "41;97")
        case .info: paint(" INFO ", "100;97")
        }
        let label = finding.image.name.language.map { paint("[\($0)]", "36") } ?? ""
        out += "\(badge) \(label) \(finding.headline)\n"

        let file = finding.image.url
        out += "    " + link(file.lastPathComponent, to: file) + "\n"

        if showImage, let rendered = image(
            file,
            intrinsicWidth: finding.image.pixelWidth,
            intrinsicHeight: finding.image.pixelHeight
        ) {
            out += rendered + "\n"
        }
    }

    public mutating func rule() {
        out += paint(String(repeating: "─", count: 60), "2") + "\n"
    }

    public func flush() {
        FileHandle.standardOutput.write(Data(out.utf8))
    }
}
