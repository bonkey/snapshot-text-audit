import Foundation

public struct TerminalStyle: Sendable {
    public let colour: Bool
    public let hyperlinks: Bool
    public let inlineImages: Bool

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
    private let imageWidth: Int
    private var out = ""

    public init(style: TerminalStyle, imageWidth: Int = 320) {
        self.style = style
        self.imageWidth = imageWidth
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
    private func image(_ url: URL) -> String? {
        guard style.inlineImages, let data = try? Data(contentsOf: url) else { return nil }
        let name = Data(url.lastPathComponent.utf8).base64EncodedString()
        let payload = data.base64EncodedString()
        return "\(Self.esc)]1337;File=name=\(name);size=\(data.count);inline=1;"
            + "width=\(imageWidth)px;preserveAspectRatio=1:\(payload)\(Self.bel)"
    }

    public mutating func heading(_ text: String) {
        out += "\n" + paint(text, "1") + "\n"
    }

    public mutating func note(_ text: String) {
        out += paint(text, "2") + "\n"
    }

    public mutating func finding(_ finding: Finding, showImage: Bool) {
        let badge = switch finding.severity {
        case .error: paint(" TRUNCATED ", "41;97")
        case .info: paint(" INFO ", "100;97")
        }
        let label = finding.image.name.language.map { paint("[\($0)]", "36") } ?? ""
        out += "\(badge) \(label) \(finding.headline)\n"

        let file = finding.image.url
        out += "    " + link(file.lastPathComponent, to: file) + "\n"

        if showImage, let rendered = image(file) {
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
