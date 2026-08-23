import GetOudioCore
import SwiftUI

enum SettingsMetrics {
    static let sectionCornerRadius: CGFloat = 20
    static let rowCornerRadius: CGFloat = 14
    static let sectionPadding: CGFloat = 16
    static let contentMaxWidth: CGFloat = LayoutConstants.settingsContentMaxWidth
    static let contentTopInset: CGFloat = 54
    static let contentBottomInset: CGFloat = 96
    static let sectionTitleFont = Font.system(size: 12, weight: .semibold)
    static let groupTitleFont = Font.system(size: 12.5, weight: .semibold)
}

struct SettingsAttentionPresentation {
    let items: Set<SettingsAttentionItem>
    let highlightRequestID: Int
    let scrollTarget: SettingsAttentionItem?

    static let none = SettingsAttentionPresentation(items: [], highlightRequestID: 0, scrollTarget: nil)

    func highlightRequest(for item: SettingsAttentionItem) -> Int {
        items.contains(item) ? highlightRequestID : 0
    }
}

struct SettingsAttentionPulseOverlay: View {
    private static let initialDelayNanoseconds: UInt64 = 450_000_000
    private static let pulseDurationNanoseconds: UInt64 = 160_000_000
    private static let pulseCount = 3

    let requestID: Int
    @State private var isHighlighted = false

    var body: some View {
        RoundedRectangle(cornerRadius: SettingsMetrics.sectionCornerRadius, style: .continuous)
            .fill(.orange.opacity(isHighlighted ? 0.22 : 0))
            .overlay {
                RoundedRectangle(cornerRadius: SettingsMetrics.sectionCornerRadius, style: .continuous)
                    .strokeBorder(.orange.opacity(isHighlighted ? 0.8 : 0), lineWidth: 2)
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .task(id: requestID) {
                resetHighlight()
                guard requestID > 0 else { return }
                defer { resetHighlight() }
                guard await wait(Self.initialDelayNanoseconds) else { return }
                for _ in 0..<Self.pulseCount {
                    withAnimation(.easeInOut(duration: 0.16)) { isHighlighted = true }
                    guard await wait(Self.pulseDurationNanoseconds) else { return }
                    withAnimation(.easeInOut(duration: 0.16)) { isHighlighted = false }
                    guard await wait(Self.pulseDurationNanoseconds) else { return }
                }
            }
            .onDisappear(perform: resetHighlight)
    }

    private func resetHighlight() {
        withTransaction(Transaction(animation: nil)) { isHighlighted = false }
    }

    private func wait(_ nanoseconds: UInt64) async -> Bool {
        do {
            try await Task.sleep(nanoseconds: nanoseconds)
            return !Task.isCancelled
        } catch {
            return false
        }
    }
}

private enum SettingsSurface {
    static func pageTint(for scheme: ColorScheme) -> Color {
        scheme == .light ? Color.black.opacity(0.025) : Color.white.opacity(0.035)
    }

    static func cardFill(for scheme: ColorScheme) -> Color {
        scheme == .light ? Color.white.opacity(0.72) : Color.white.opacity(0.075)
    }

    static func controlFill(for scheme: ColorScheme) -> Color {
        scheme == .light ? Color.black.opacity(0.045) : Color.white.opacity(0.07)
    }

    static func border(for scheme: ColorScheme) -> Color {
        scheme == .light ? Color.black.opacity(0.095) : Color.white.opacity(0.105)
    }
}

struct SettingsRootBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            Rectangle().fill(.thinMaterial)
            Rectangle().fill(SettingsSurface.pageTint(for: colorScheme))
        }
        .ignoresSafeArea()
    }
}

private struct SettingsCardBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        RoundedRectangle(cornerRadius: SettingsMetrics.sectionCornerRadius, style: .continuous)
            .fill(.regularMaterial)
            .overlay {
                RoundedRectangle(cornerRadius: SettingsMetrics.sectionCornerRadius, style: .continuous)
                    .fill(SettingsSurface.cardFill(for: colorScheme))
            }
            .overlay {
                RoundedRectangle(cornerRadius: SettingsMetrics.sectionCornerRadius, style: .continuous)
                    .strokeBorder(SettingsSurface.border(for: colorScheme), lineWidth: 0.7)
            }
            .shadow(color: .black.opacity(colorScheme == .light ? 0.05 : 0.18), radius: 16, x: 0, y: 8)
    }
}

private struct SettingsGroupedRowBackgroundModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: SettingsMetrics.rowCornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: SettingsMetrics.rowCornerRadius, style: .continuous)
                    .fill(SettingsSurface.controlFill(for: colorScheme))
                    .allowsHitTesting(false)
            }
            .overlay {
                RoundedRectangle(cornerRadius: SettingsMetrics.rowCornerRadius, style: .continuous)
                    .strokeBorder(SettingsSurface.border(for: colorScheme), lineWidth: 0.6)
                    .allowsHitTesting(false)
            }
    }
}

extension View {
    func settingsGroupedRowBackground() -> some View {
        modifier(SettingsGroupedRowBackgroundModifier())
    }
}

struct SettingsSection<Content: View, Footer: View, CardOverlay: View>: View {
    let title: String
    let systemImage: String
    let showsTitle: Bool
    let contentPadding: CGFloat
    let clipsCardContent: Bool
    let content: Content
    let footer: Footer
    let cardOverlay: CardOverlay

    init(
        _ title: String,
        systemImage: String = "gearshape",
        showsTitle: Bool = true,
        contentPadding: CGFloat = SettingsMetrics.sectionPadding,
        clipsCardContent: Bool = false,
        @ViewBuilder content: () -> Content,
        @ViewBuilder footer: () -> Footer = { EmptyView() },
        @ViewBuilder cardOverlay: () -> CardOverlay = { EmptyView() }
    ) {
        self.title = title
        self.systemImage = systemImage
        self.showsTitle = showsTitle
        self.contentPadding = contentPadding
        self.clipsCardContent = clipsCardContent
        self.content = content()
        self.footer = footer()
        self.cardOverlay = cardOverlay()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            if showsTitle {
                HStack(spacing: 6) {
                    Image(systemName: systemImage)
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 15, alignment: .center)
                    Text(title).font(SettingsMetrics.sectionTitleFont)
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
            }

            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 0) { content }
                    .padding(contentPadding)
                if !(footer is EmptyView) {
                    Divider()
                    VStack(alignment: .leading, spacing: 4) { footer }
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, SettingsMetrics.sectionPadding)
                        .padding(.vertical, 8)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .modifier(SettingsCardContentClipModifier(isEnabled: clipsCardContent))
            .background(SettingsCardBackground())
            .overlay { cardOverlay }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct SettingsCardContentClipModifier: ViewModifier {
    let isEnabled: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if isEnabled {
            content.clipShape(RoundedRectangle(cornerRadius: SettingsMetrics.sectionCornerRadius, style: .continuous))
        } else {
            content
        }
    }
}

struct SettingsForm<Content: View>: View {
    let spacing: CGFloat
    let scrollTarget: String?
    let scrollRequestID: Int
    let content: Content

    init(
        spacing: CGFloat = 30,
        scrollTarget: String? = nil,
        scrollRequestID: Int = 0,
        @ViewBuilder content: () -> Content
    ) {
        self.spacing = spacing
        self.scrollTarget = scrollTarget
        self.scrollRequestID = scrollRequestID
        self.content = content()
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 0) {
                    Color.clear.frame(height: SettingsMetrics.contentTopInset)
                    VStack(alignment: .leading, spacing: spacing) { content }
                        .frame(maxWidth: SettingsMetrics.contentMaxWidth, alignment: .leading)
                    Color.clear.frame(height: SettingsMetrics.contentBottomInset)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollClipDisabled()
            .scrollContentBackground(.hidden)
            .task(id: scrollRequestID) {
                guard scrollRequestID > 0, let scrollTarget else { return }
                try? await Task.sleep(nanoseconds: 150_000_000)
                guard !Task.isCancelled else { return }
                withAnimation(.easeOut(duration: 0.25)) {
                    proxy.scrollTo(scrollTarget, anchor: .top)
                }
            }
        }
    }
}
