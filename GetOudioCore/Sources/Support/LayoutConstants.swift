import Foundation

/// Shared layout constants for the settings window.
/// Keep these in sync with the visual design — both AppKit window setup and
/// SwiftUI views reference the same values to ensure alignment.
public enum LayoutConstants {
    /// Corner radius applied to the settings window and main content clip shape.
    public static let windowCornerRadius: CGFloat = 26
    /// Corner radius applied to the settings sidebar background.
    public static let sidebarCornerRadius: CGFloat = 20
    /// Horizontal margin between window edge and content, and between sidebar and detail panel.
    public static let outerMargin: CGFloat = 22
    /// Margin between the settings sidebar and the window's top edge.
    public static let sidebarTopMargin: CGFloat = 19
    /// Margin between the settings sidebar and the window's bottom edge.
    public static let sidebarBottomMargin: CGFloat = 21
    /// Width of the settings sidebar.
    public static let sidebarWidth: CGFloat = 260
    /// Maximum width of the settings content area (right panel).
    public static let settingsContentMaxWidth: CGFloat = 760
}
