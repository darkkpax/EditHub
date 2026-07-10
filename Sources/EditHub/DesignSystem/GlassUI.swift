import SwiftUI

// MARK: - Design tokens
//
// EditHub uses the native macOS look: system materials, the user's accent
// color, standard controls and typography. The main window stays native; the
// compact project creator reuses the small Liquid Glass card style from the
// standalone ProjectCreator app.

enum Theme {
    /// The app accent. Follows the user's system accent color.
    static let accent = Color.accentColor

    static let cardRadius: CGFloat = 10
    static let controlRadius: CGFloat = 7

    static let pagePadding: CGFloat = 24
    static let sectionSpacing: CGFloat = 18
}

/// Standard motion. Native, restrained.
enum Motion {
    static let standard = Animation.smooth(duration: 0.28)
    static let snappy = Animation.snappy(duration: 0.24)
    static let quick = Animation.easeInOut(duration: 0.18)
}

// MARK: - Compatibility aliases
//
// Older call sites reference these names. They now resolve to native styling
// so the whole app shares one visual language.

enum LiquidGlassPalette {
    static let blue1 = Color.accentColor
    static let blue2 = Color.accentColor
}

enum AppUI {
    static let pagePadding = Theme.pagePadding
    static let sectionSpacing = Theme.sectionSpacing
    static let controlHeight: CGFloat = 28
    static let cardRadius = Theme.cardRadius
    static let controlRadius = Theme.controlRadius
}

// Restrained, native-feeling motion. A small, consistent set — no overshoot,
// no playful springs. macOS apps move subtly; these match that.
enum SoftIOSMotion {
    static let hover = Animation.easeOut(duration: 0.16)
    static let press = Animation.easeOut(duration: 0.12)
    static let pressRelease = Animation.spring(response: 0.34, dampingFraction: 0.56)
    static let state = Animation.smooth(duration: 0.24)
    static let text = Animation.easeInOut(duration: 0.2)
    static let progress = Animation.easeInOut(duration: 0.18)
    static let entry = Animation.smooth(duration: 0.3)
    static let pause = Animation.smooth(duration: 0.24)
    static let morph = Animation.smooth(duration: 0.26)
    static let bouncySlide = Animation.snappy(duration: 0.28)
    static let controlSwap = Animation.smooth(duration: 0.3)
    static let modal = Animation.smooth(duration: 0.28)
    /// Spring with overshoot — used for icon pop-in, like VPN app circles.
    static let iconPop = Animation.spring(response: 0.45, dampingFraction: 0.6)
    /// Quick squash-on-press, springy release (Telegram iOS style).
    static let tapSpring = Animation.spring(response: 0.36, dampingFraction: 0.52)
}

// MARK: - App backdrop

/// Animated blob backdrop — three soft radial blobs that slowly drift,
/// giving Liquid Glass surfaces uneven, colorful content to refract
/// (the same trick Apple uses in Music, Freeform, and Control Center).
struct WindowBackdrop: View {
    @State private var phase: Double = 0

    var body: some View {
        Rectangle()
            .fill(.background)
            .overlay {
                TimelineView(.animation(minimumInterval: 1/30)) { tl in
                    let t = tl.date.timeIntervalSinceReferenceDate * 0.18
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
            .ignoresSafeArea()
    }
}

// MARK: - Panel backdrop

/// Backdrop for sidebars: thin system material so the Liquid Glass controls
/// can refract the animated blobs behind them.
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

/// Shared top chrome for the project browser. Native material supplies the
/// live backdrop blur; the faint diagonal frost matches Flutter's glass strip.
struct FrostedHeaderStrip: View {
    var body: some View {
        Rectangle()
            .fill(.ultraThinMaterial)
            .overlay {
                LinearGradient(
                    colors: [.white.opacity(0.08), .white.opacity(0.025), .clear],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(.white.opacity(0.10))
                    .frame(height: 1)
            }
    }
}

// MARK: - Liquid Glass card surface

extension View {
    func glassPrimaryText(size: CGFloat) -> some View {
        font(.system(size: size, weight: .medium))
    }

    func glassSecondaryText(size: CGFloat) -> some View {
        font(.system(size: size, weight: .medium))
    }

    func glassButtonText(size: CGFloat) -> some View {
        font(.system(size: size, weight: .semibold))
    }

    func glassEmphasizedButtonText(size: CGFloat) -> some View {
        font(.system(size: size, weight: .semibold))
    }

    func liquidGlassControl(
        cornerRadius: CGFloat = 10,
        minHeight: CGFloat = 28,
        horizontalPadding: CGFloat = 11,
        expandsToMaxWidth: Bool = true,
        interactive: Bool = true,
        accentColor: Color = .white
    ) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        return Group {
            if expandsToMaxWidth {
                self
                    .padding(.horizontal, horizontalPadding)
                    .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .leading)
            } else {
                self
                    .padding(.horizontal, horizontalPadding)
                    .frame(minHeight: minHeight, alignment: .leading)
            }
        }
        .background {
            shape
                .fill(.clear)
                .glassEffect(interactive ? .regular.interactive() : .regular, in: shape)
        }
        .modifier(SoftGlassHoverModifier(enabled: interactive))
    }

    func liquidGlassButton(
        cornerRadius: CGFloat = 10,
        accentColor: Color = .white
    ) -> some View {
        buttonStyle(SoftIOSButtonStyle())
            .liquidGlassControl(
                cornerRadius: cornerRadius,
                minHeight: 28,
                horizontalPadding: 0,
                accentColor: accentColor
            )
    }

    /// A Liquid Glass card — the building block for rows, panels and floating
    /// surfaces throughout the app. Selected cards take an accent tint.
    func glassCard(
        cornerRadius: CGFloat = Theme.cardRadius,
        selected: Bool = false,
        interactive: Bool = true,
        accent: Color = Theme.accent
    ) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        var glass: Glass = .regular
        if selected { glass = glass.tint(accent.opacity(0.55)) }
        if interactive { glass = glass.interactive() }
        return self.glassEffect(glass, in: shape)
    }
}

private struct SoftGlassHoverModifier: ViewModifier {
    @State private var isHovered = false
    var enabled = true

    func body(content: Content) -> some View {
        content
            // Liquid Glass already responds to hover via `.interactive()`; keep
            // the extra scale tiny so it reads as native, not springy.
            .scaleEffect(enabled && isHovered ? 1.005 : 1.0)
            .onHover { hovering in
                guard enabled else { return }
                withAnimation(SoftIOSMotion.hover) {
                    isHovered = hovering
                }
            }
    }
}

struct SoftIOSButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(SoftIOSMotion.press, value: configuration.isPressed)
    }
}

// MARK: - Animated action circle (VPN-style)

/// Round accent circle with icon — presses with spring squash, flashes on tap.
/// Mirrors the action circles in the chameleonvpn mini-app.
struct ActionCircle: View {
    let systemImage: String
    let label: String
    var accent: Color = Theme.accent
    var onTap: () -> Void

    @State private var isPressed = false
    @State private var flashTick = false
    @State private var isHovered = false

    var body: some View {
        Button {
            withAnimation(SoftIOSMotion.tapSpring) { flashTick.toggle() }
            onTap()
        } label: {
            VStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(flashTick
                              ? accent
                              : accent.opacity(isHovered ? 0.2 : 0.14))
                        .frame(width: 44, height: 44)
                        .animation(.easeOut(duration: 0.55), value: flashTick)

                    Image(systemName: systemImage)
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(flashTick ? .white : accent)
                        .scaleEffect(isPressed ? 0.82 : 1)
                        .animation(SoftIOSMotion.tapSpring, value: isPressed)
                        .symbolEffect(.bounce, value: flashTick)
                }
                .scaleEffect(isPressed ? 0.88 : 1)
                .animation(SoftIOSMotion.tapSpring, value: isPressed)

                Text(label)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(accent)
            }
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in if !isPressed { withAnimation { isPressed = true } } }
                .onEnded { _ in withAnimation(SoftIOSMotion.pressRelease) { isPressed = false } }
        )
    }
}

// MARK: - Animated toolbar icon button (VPN-style)

/// Small icon button with hover glow and press-spring. Used in toolbars.
struct AnimatedIconButton: View {
    let systemImage: String
    var color: Color = .secondary
    var size: CGFloat = 13
    var help: String = ""
    var onTap: () -> Void

    @State private var isPressed = false
    @State private var isHovered = false

    var body: some View {
        Button { onTap() } label: {
            Image(systemName: systemImage)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(isHovered ? color : color.opacity(0.7))
                .frame(width: 28, height: 28)
                .background(
                    Circle()
                        .fill(isHovered ? color.opacity(0.12) : Color.clear)
                        .animation(SoftIOSMotion.hover, value: isHovered)
                )
                .scaleEffect(isPressed ? 0.86 : 1)
                .animation(SoftIOSMotion.tapSpring, value: isPressed)
        }
        .buttonStyle(.plain)
        .help(help)
        .onHover { isHovered = $0 }
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in if !isPressed { withAnimation { isPressed = true } } }
                .onEnded { _ in withAnimation(SoftIOSMotion.pressRelease) { isPressed = false } }
        )
    }
}

// MARK: - Entrance animation modifier

/// Applies a "pop in from below" entrance — like VPN app's .fade class.
extension View {
    func popEntrance(delay: Double = 0) -> some View {
        modifier(PopEntranceModifier(delay: delay))
    }
}

private struct PopEntranceModifier: ViewModifier {
    let delay: Double
    @State private var appeared = false

    func body(content: Content) -> some View {
        content
            .opacity(appeared ? 1 : 0)
            .scaleEffect(appeared ? 1 : 0.92)
            .offset(y: appeared ? 0 : 10)
            .onAppear {
                withAnimation(.spring(response: 0.42, dampingFraction: 0.7).delay(delay)) {
                    appeared = true
                }
            }
    }
}
