import AppKit
import SwiftUI

private enum MarkdownTypography {
    static let bodyFontSize: CGFloat = 15
    static let lineSpacing: CGFloat = 18
    static let paragraphSpacing: CGFloat = bodyFontSize * 2
    static let contentHorizontalPadding: CGFloat = 12
    static let contentVerticalPadding: CGFloat = 12
    static let listItemSpacing: CGFloat = 18
}

enum SettingsDocumentSectionID: String, CaseIterable, Hashable {
    case overview = "授权/关于"
    case transcoding = "音频重编码"
    case ncm = "NCM 解密"
    case appleMusic = "Apple Music 下载"
    case recording = "录音"
}

struct SettingsDocumentSection {
    let blocks: [SettingsMarkdownBlock]
    let errorMessage: String?
}

struct SettingsMarkdownBlock: Identifiable {
    enum Kind {
        case paragraph(AttributedString)
        case list([AttributedString])
        case image(URL, CGFloat?)
    }

    let id = UUID()
    let kind: Kind
}

enum SettingsDocumentationStore {
    static func section(for id: SettingsDocumentSectionID) -> SettingsDocumentSection {
        cachedSections[id] ?? SettingsDocumentSection(
            blocks: [],
            errorMessage: "文档加载失败：找不到 \(id.rawValue) 章节"
        )
    }

    private static let cachedSections = loadSections()

    private static func loadSections() -> [SettingsDocumentSectionID: SettingsDocumentSection] {
        do {
            let document = try loadDocument()
            return Dictionary(uniqueKeysWithValues: SettingsDocumentSectionID.allCases.map { id in
                let sectionMarkdown = markdownSection(named: id.rawValue, in: document.markdown)
                let section = sectionMarkdown.isEmpty
                    ? SettingsDocumentSection(
                        blocks: [],
                        errorMessage: "文档加载失败：找不到 \(id.rawValue) 章节"
                    )
                    : SettingsDocumentSection(
                        blocks: parseBlocks(sectionMarkdown, resourceRoot: document.resourceRoot),
                        errorMessage: nil
                    )

                return (id, section)
            })
        } catch {
            return Dictionary(uniqueKeysWithValues: SettingsDocumentSectionID.allCases.map { id in
                (
                    id,
                    SettingsDocumentSection(
                        blocks: [],
                        errorMessage: "文档加载失败：\(error.localizedDescription)"
                    )
                )
            })
        }
    }

    private static func loadDocument() throws -> (markdown: String, resourceRoot: URL) {
        guard let url = Bundle.main.url(
            forResource: "Get Oudio Doc",
            withExtension: "md",
            subdirectory: "Documentation"
        ) else {
            throw CocoaError(.fileNoSuchFile)
        }

        return (try String(contentsOf: url, encoding: .utf8), url.deletingLastPathComponent())
    }

    private static func markdownSection(named title: String, in markdown: String) -> String {
        var isCollecting = false
        var collected: [String] = []

        for line in markdown.components(separatedBy: .newlines) {
            if line.hasPrefix("# ") {
                let heading = String(line.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                if isCollecting {
                    break
                }
                isCollecting = heading == title
                continue
            }

            if isCollecting {
                collected.append(line)
            }
        }

        return collected.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func parseBlocks(_ markdown: String, resourceRoot: URL) -> [SettingsMarkdownBlock] {
        var blocks: [SettingsMarkdownBlock] = []
        var paragraphLines: [String] = []
        var listItems: [AttributedString] = []

        func flushParagraph() {
            guard !paragraphLines.isEmpty else { return }
            let text = paragraphLines.joined(separator: " ")
            blocks.append(SettingsMarkdownBlock(kind: .paragraph(parseInlineMarkdown(text))))
            paragraphLines.removeAll()
        }

        func flushList() {
            guard !listItems.isEmpty else { return }
            blocks.append(SettingsMarkdownBlock(kind: .list(listItems)))
            listItems.removeAll()
        }

        for rawLine in markdown.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)

            if line.isEmpty {
                flushParagraph()
                flushList()
                continue
            }

            if let image = parseImage(line, resourceRoot: resourceRoot) {
                flushParagraph()
                flushList()
                blocks.append(SettingsMarkdownBlock(kind: .image(image.url, image.preferredWidth)))
                continue
            }

            if line.hasPrefix("- ") {
                flushParagraph()
                listItems.append(parseInlineMarkdown(String(line.dropFirst(2))))
                continue
            }

            flushList()
            paragraphLines.append(line)
        }

        flushParagraph()
        flushList()
        return blocks
    }

    private static func parseImage(_ line: String, resourceRoot: URL) -> (url: URL, preferredWidth: CGFloat?)? {
        guard line.hasPrefix("!["),
              let altEnd = line.firstIndex(of: "]"),
              line[line.index(after: altEnd)...].hasPrefix("("),
              line.hasSuffix(")")
        else {
            return nil
        }

        let altText = String(line[line.index(line.startIndex, offsetBy: 2)..<altEnd])
        let pathStart = line.index(altEnd, offsetBy: 2)
        let pathEnd = line.index(before: line.endIndex)
        let rawPath = String(line[pathStart..<pathEnd])
        let decodedPath = rawPath.removingPercentEncoding ?? rawPath
        let digits = altText.filter(\.isNumber)
        let width = digits.isEmpty ? nil : CGFloat((Double(digits) ?? 0).clamped(to: 80...640))

        return (resourceRoot.appendingPathComponent(decodedPath), width)
    }

    private static func parseInlineMarkdown(_ text: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace
        )

        return (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
    }
}

struct MarkdownDocumentView: View {
    let id: SettingsDocumentSectionID

    init(_ id: SettingsDocumentSectionID) {
        self.id = id
    }

    var body: some View {
        SettingsSection("使用说明", systemImage: "text.book.closed") {
            MarkdownDocumentContent(id)
        }
    }
}

struct MarkdownDocumentContent: View {
    let section: SettingsDocumentSection

    init(_ id: SettingsDocumentSectionID) {
        section = SettingsDocumentationStore.section(for: id)
    }

    var body: some View {
            VStack(alignment: .leading, spacing: MarkdownTypography.paragraphSpacing) {
                if let errorMessage = section.errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                ForEach(section.blocks) { block in
                    blockView(block)
                }
            }
            .padding(.horizontal, MarkdownTypography.contentHorizontalPadding)
            .padding(.vertical, MarkdownTypography.contentVerticalPadding)
            .textSelection(.enabled)
    }

    @ViewBuilder
    private func blockView(_ block: SettingsMarkdownBlock) -> some View {
        switch block.kind {
        case .paragraph(let text):
            MarkdownTextBlock(text)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .list(let items):
            VStack(alignment: .leading, spacing: MarkdownTypography.listItemSpacing) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .top, spacing: 8) {
                        Text("•")
                            .font(.system(size: MarkdownTypography.bodyFontSize))
                            .foregroundStyle(.secondary)
                            .padding(.top, 1)
                        MarkdownTextBlock(item)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        case .image(let url, let preferredWidth):
            SettingsMarkdownImage(url: url, preferredWidth: preferredWidth)
        }
    }
}

private struct SettingsMarkdownImage: View {
    let url: URL
    let preferredWidth: CGFloat?

    var body: some View {
        if let image = NSImage(contentsOf: url) {
            HStack {
                Spacer(minLength: 0)
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: preferredWidth ?? 520)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(.quaternary, lineWidth: 0.5)
                    }
                    .shadow(color: .black.opacity(0.12), radius: 10, x: 0, y: 6)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
        }
    }
}

private struct MarkdownTextBlock: View {
    let text: AttributedString
    @State private var height: CGFloat = 45

    init(_ text: AttributedString) {
        self.text = text
    }

    var body: some View {
        GeometryReader { proxy in
            MarkdownTextView(text, width: proxy.size.width, height: $height)
        }
        .frame(height: height)
    }
}

private struct MarkdownTextView: NSViewRepresentable {
    let text: AttributedString
    let width: CGFloat
    @Binding var height: CGFloat

    init(_ text: AttributedString, width: CGFloat, height: Binding<CGFloat>) {
        self.text = text
        self.width = width
        _height = height
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> LinkTextView {
        let textView = LinkTextView()
        textView.delegate = context.coordinator
        textView.drawsBackground = false
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = true
        textView.textContainerInset = .zero
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.linkTextAttributes = [
            .foregroundColor: NSColor.linkColor,
            .underlineStyle: NSUnderlineStyle.single.rawValue
        ]
        textView.setContentCompressionResistancePriority(.required, for: .vertical)
        textView.setContentHuggingPriority(.required, for: .vertical)
        textView.translatesAutoresizingMaskIntoConstraints = false
        return textView
    }

    func updateNSView(_ nsView: LinkTextView, context: Context) {
        let attributedText = makeAttributedText()
        nsView.textStorage?.setAttributedString(attributedText)
        guard let textContainer = nsView.textContainer,
              let layoutManager = nsView.layoutManager
        else {
            return
        }

        let resolvedWidth = max(width, 1)
        nsView.frame.size.width = resolvedWidth
        textContainer.containerSize = NSSize(width: resolvedWidth, height: .greatestFiniteMagnitude)
        textContainer.widthTracksTextView = true
        layoutManager.ensureLayout(for: textContainer)
        let measuredHeight = ceil(layoutManager.usedRect(for: textContainer).height) + 3
        if abs(height - measuredHeight) > 0.5 {
            DispatchQueue.main.async {
                height = measuredHeight
            }
        }
    }

    private func makeAttributedText() -> NSAttributedString {
        let attributedText = NSMutableAttributedString(attributedString: NSAttributedString(text))
        let fullRange = NSRange(location: 0, length: attributedText.length)
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .justified
        paragraphStyle.lineSpacing = MarkdownTypography.lineSpacing
        paragraphStyle.paragraphSpacing = MarkdownTypography.paragraphSpacing
        paragraphStyle.lineBreakMode = .byWordWrapping

        attributedText.addAttributes(
            [
                .font: NSFont.systemFont(ofSize: MarkdownTypography.bodyFontSize),
                .foregroundColor: NSColor.labelColor,
                .paragraphStyle: paragraphStyle
            ],
            range: fullRange
        )
        return attributedText
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
            if let url = link as? URL {
                NSWorkspace.shared.open(url)
                return true
            }

            if let string = link as? String, let url = URL(string: string) {
                NSWorkspace.shared.open(url)
                return true
            }

            return false
        }
    }
}

private final class LinkTextView: NSTextView {
    private var trackingAreaReference: NSTrackingArea?

    override func updateTrackingAreas() {
        if let trackingAreaReference {
            removeTrackingArea(trackingAreaReference)
        }

        let trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .activeInActiveApp, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
        trackingAreaReference = trackingArea
        super.updateTrackingAreas()
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        cursorForEvent(event).set()
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: .arrow)
    }

    private func cursorForEvent(_ event: NSEvent) -> NSCursor {
        guard hasLink(at: event) else {
            return .arrow
        }

        return .pointingHand
    }

    private func hasLink(at event: NSEvent) -> Bool {
        guard let layoutManager,
              let textContainer,
              let textStorage,
              textStorage.length > 0
        else {
            return false
        }

        var point = convert(event.locationInWindow, from: nil)
        point.x -= textContainerInset.width
        point.y -= textContainerInset.height

        let glyphIndex = layoutManager.glyphIndex(for: point, in: textContainer)
        guard glyphIndex < layoutManager.numberOfGlyphs else {
            return false
        }

        let glyphRect = layoutManager.boundingRect(forGlyphRange: NSRange(location: glyphIndex, length: 1), in: textContainer)
        guard glyphRect.insetBy(dx: -2, dy: -3).contains(point) else {
            return false
        }

        let characterIndex = layoutManager.characterIndexForGlyph(at: glyphIndex)
        guard characterIndex < textStorage.length else {
            return false
        }

        return textStorage.attribute(.link, at: characterIndex, effectiveRange: nil) != nil
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
