import SwiftUI

/// Small compatibility layer for older call sites. Visual styling is supplied
/// by native SwiftUI controls and system materials in the views themselves.
enum Theme {
    static let accent = Color.accentColor

    // Corner radii, named for the thing they wrap. The values match what the
    // views actually draw — previously `cardRadius`/`controlRadius` claimed
    // 10/7 while every call site hard-coded 8/12/16/24, so the tokens meant
    // nothing. Keep new radii on this scale instead of adding a literal.
    /// Thumbnails, small chips, inline stat pills.
    static let smallRadius: CGFloat = 8
    /// Cards, list tiles, the detail header's icon well.
    static let cardRadius: CGFloat = 12
    /// Text fields and buttons inside popovers.
    static let controlRadius: CGFloat = 16
    /// Floating popovers and sheets.
    static let popoverRadius: CGFloat = 24

    static let pagePadding: CGFloat = 24
    static let sectionSpacing: CGFloat = 18

    // Shared chrome metrics keep sidebar and detail actions on one visual grid.
    // Both headers sit under the transparent title bar, so `headerTopInset`
    // clears the traffic lights and `headerContentHeight` is the space below it
    // that holds the controls. Their sum is the full header height that content
    // must be inset by so nothing starts hidden underneath.
    static let headerTopInset: CGFloat = 10
    // 32pt controls + 6pt row gap + 34pt search + 12pt bottom inset.
    // Keep this arithmetic explicit so enlarging a control cannot silently
    // consume the visible space below the search field again.
    static let headerContentHeight: CGFloat = 84
    static let headerHeight: CGFloat = headerTopInset + headerContentHeight
    static let controlHeight: CGFloat = 32
    static let controlSpacing: CGFloat = 6
    static let headerHorizontalPadding: CGFloat = 14
    /// Compact icon buttons in the sidebar header, matched to the system
    /// sidebar-toggle control so the row reads as one set.
    static let headerButtonSize: CGFloat = 32
}

extension View {
    /// A consistent symbol canvas for icon-only controls in app headers.
    func headerActionLabel() -> some View {
        frame(width: Theme.controlHeight, height: Theme.controlHeight)
            .contentShape(.circle)
    }

    /// Subtle symbol hover feedback. Press handling deliberately stays on the
    /// enclosing Button so the glyph never becomes a competing hit target.
    func tactileSymbol() -> some View {
        modifier(TactileSymbolModifier())
    }
}

enum Motion {
    /// Pointer-down and other immediate feedback.
    static let press = Animation.interactiveSpring(response: 0.16, dampingFraction: 0.78)
    /// Selection, toggles, symbol replacement, and small state changes.
    static let feedback = Animation.spring(duration: 0.24, bounce: 0.22)
    /// General UI state changes: quick with a small, macOS-appropriate overshoot.
    static let state = Animation.spring(duration: 0.32, bounce: 0.16)
    /// Insertions, sheets, banners, and disclosure content.
    static let reveal = Animation.spring(duration: 0.4, bounce: 0.12)
    /// Shared geometry and Liquid Glass shape changes.
    static let morph = Animation.spring(duration: 0.46, bounce: 0.18)
    /// Progress and text should settle without visible bounce.
    static let continuous = Animation.smooth(duration: 0.22)

    static let standard = state
    static let snappy = feedback
    static let quick = press
}

/// Intent-named aliases over `Motion`, so download/service code can say what a
/// transition *is* rather than which curve it uses. Only the names actually in
/// use are kept — five more (`hover`, `press`, `pressRelease`, `iconPop`,
/// `tapSpring`) were never referenced and are gone; use `Motion` directly for
/// new call sites that don't have a distinct intent to name.
enum SoftIOSMotion {
    static let state = Motion.state
    static let text = Motion.continuous
    static let progress = Motion.continuous
    static let entry = Motion.reveal
    static let pause = Motion.feedback
    static let morph = Motion.morph
    static let bouncySlide = Motion.state
    static let controlSwap = Motion.state
    static let modal = Motion.reveal
}

private struct TactileSymbolModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(reduceMotion ? 1 : (isHovered ? 1.06 : 1))
            .animation(reduceMotion ? .none : Motion.feedback, value: isHovered)
            .onHover { isHovered = $0 }
    }
}

// MARK: - App backdrop

struct WindowBackdrop: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Rectangle()
            .fill(.background)
            .overlay {
                // A full-window field of slowly drifting blobs is exactly the
                // kind of large-surface ambient motion Reduce Motion exists to
                // suppress, and redrawing it forever costs battery for decoration.
                // Freeze it to a static composition instead of dropping it, so
                // the window keeps its depth without the perpetual animation.
                if reduceMotion {
                    blobs(at: 0)
                } else {
                    TimelineView(.animation(minimumInterval: 1 / 30)) { tl in
                        blobs(at: tl.date.timeIntervalSinceReferenceDate * 0.18)
                    }
                }
            }
            .ignoresSafeArea()
    }

    /// The three drifting accent blobs at animation time `t`. At `t == 0` this
    /// is the static composition used under Reduce Motion.
    private func blobs(at t: Double) -> some View {
        ZStack {
            // Large top-left blob
            EllipticalGradient(
                colors: [Theme.accent.opacity(0.14), .clear],
                center: UnitPoint(
                    x: 0.12 + 0.08 * sin(t * 0.7),
                    y: 0.08 + 0.06 * cos(t * 0.5)
                ),
                endRadiusFraction: 0.62
            )

            // Mid right blob
            EllipticalGradient(
                colors: [Theme.accent.opacity(0.09), .clear],
                center: UnitPoint(
                    x: 0.82 + 0.07 * cos(t * 0.6 + 1.2),
                    y: 0.38 + 0.09 * sin(t * 0.4 + 0.8)
                ),
                endRadiusFraction: 0.52
            )

            // Bottom-center accent blob
            EllipticalGradient(
                colors: [Theme.accent.opacity(0.07), .clear],
                center: UnitPoint(
                    x: 0.45 + 0.10 * sin(t * 0.35 + 2.1),
                    y: 0.85 + 0.05 * cos(t * 0.55 + 0.3)
                ),
                endRadiusFraction: 0.45
            )
        }
    }
}

// MARK: - Panel backdrop

struct DefaultLiquidGlassBackground: View {
    var body: some View {
        ZStack {
            WindowBackdrop()
            // Thin frosted layer so the panel reads slightly separate from the
            // detail pane while still letting the blobs show through.
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()
        }
    }
}