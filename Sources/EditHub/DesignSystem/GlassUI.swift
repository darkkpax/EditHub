import SwiftUI
import AppKit

enum SoftIOSMotion {
    static let hover = Animation.spring(response: 0.34, dampingFraction: 0.84, blendDuration: 0.12)
    static let press = Animation.interactiveSpring(response: 0.26, dampingFraction: 0.8, blendDuration: 0.14)
    static let state = Animation.easeInOut(duration: 0.24)
    static let text = Animation.easeInOut(duration: 0.2)
    static let progress = Animation.easeInOut(duration: 0.18)
    static let entry = Animation.spring(response: 0.46, dampingFraction: 0.88, blendDuration: 0.16)
    static let pause = Animation.spring(response: 0.3, dampingFraction: 0.72, blendDuration: 0.15)
    static let morph = Animation.spring(response: 0.38, dampingFraction: 0.9, blendDuration: 0.12)
    static let controlSwap = Animation.spring(response: 0.48, dampingFraction: 0.94, blendDuration: 0.16)
    static let modal = Animation.spring(response: 0.42, dampingFraction: 0.86, blendDuration: 0.16)
}

// MARK: - Typography
// Унифицировано с GoogleDropboxDownloader: обычный системный шрифт, без rounded/bold.

extension View {
    func glassPrimaryText(size: CGFloat) -> some View {
        self.font(.system(size: size, weight: .medium))
    }

    func glassSecondaryText(size: CGFloat) -> some View {
        self.font(.system(size: size, weight: .medium))
    }

    func glassButtonText(size: CGFloat) -> some View {
        self.font(.system(size: size, weight: .semibold))
    }

    func glassEmphasizedButtonText(size: CGFloat) -> some View {
        self.font(.system(size: size, weight: .semibold))
    }
}

// MARK: - Palette

enum LiquidGlassPalette {
    static let blue1 = Color(red: 0.22, green: 0.55, blue: 0.95)
    static let blue2 = Color(red: 0.18, green: 0.75, blue: 1.00)

    static let glossStrong = Color.white.opacity(0.55)
    static let glossSoft = Color.white.opacity(0.20)

    static let edgeWhite = Color.white.opacity(0.32)
    static let edgeBlue = blue2.opacity(0.22)

    static let glowBlue = blue2.opacity(0.35)

    static let innerShadow = Color.black.opacity(0.08)
}

// MARK: - Background
// Точная копия фона из GoogleDropboxDownloader.

struct LiquidGlassBackground: View {
    private let cornerRadius: CGFloat = 10

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        Group {
            if #available(macOS 26.0, *) {
                ZStack {
                    shape
                        .fill(.regularMaterial.opacity(0.82))

                    LinearGradient(
                        colors: [Color.white.opacity(0.16), Color.clear, Color.black.opacity(0.09)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .clipShape(shape)

                    Color.black.opacity(0.12)
                        .clipShape(shape)

                    shape
                        .fill(.clear)
                        .glassEffect(.clear.tint(.white.opacity(0.2)).interactive(), in: shape)
                        .overlay(shape.stroke(.white.opacity(0.34), lineWidth: 1))
                }
            } else {
                DesktopWallpaperView(cornerRadius: cornerRadius)
            }
        }
        .clipShape(shape)
        .ignoresSafeArea()
    }
}

/// Псевдоним для совместимости с существующими вызовами в ContentView.
struct DefaultLiquidGlassBackground: View {
    var body: some View {
        LiquidGlassBackground()
    }
}

// MARK: - Variants

enum LiquidGlassButtonVariant {
    case fullWidth
    case pill
    case emphasizedPill
}

// MARK: - Controls
// Единый стиль "стеклянного контрола" — как в GoogleDropboxDownloader.

extension View {
    /// универсальная стеклянная плашка для textfield / кнопок
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
            if #available(macOS 26.0, *) {
                shape
                    .fill(.clear)
                    .glassEffect(.clear.tint(.white.opacity(0.16)), in: shape)
                    .overlay(shape.stroke(.white.opacity(0.34), lineWidth: 1))
            } else {
                shape
                    .fill(.ultraThinMaterial)
                    .overlay(shape.stroke(.white.opacity(0.34), lineWidth: 1))
            }
        }
        .modifier(SoftGlassHoverModifier(enabled: interactive))
    }

    /// стеклянная кнопка "пилюля" (для маленьких кнопок типа choose/close/open)
    func liquidGlassPillButton(cornerRadius: CGFloat = 10) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        return self
            .padding(.vertical, 4)
            .padding(.horizontal, 9)
            .compositingGroup()
            .background {
                if #available(macOS 26.0, *) {
                    shape
                        .fill(.clear)
                        .glassEffect(.clear.tint(.white.opacity(0.16)), in: shape)
                        .overlay(shape.stroke(.white.opacity(0.34), lineWidth: 1))
                } else {
                    shape
                        .fill(.ultraThinMaterial)
                        .overlay(shape.stroke(.white.opacity(0.34), lineWidth: 1))
                }
            }
            .modifier(SoftGlassHoverModifier())
    }

    /// более контрастная стеклянная "пилюля" для кнопки внутри стеклянной строки
    func liquidGlassPillButtonEmphasized(cornerRadius: CGFloat = 10) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        return self
            .padding(.vertical, 4)
            .padding(.horizontal, 9)
            .compositingGroup()
            .background {
                if #available(macOS 26.0, *) {
                    shape
                        .fill(.clear)
                        .glassEffect(.clear.tint(.white.opacity(0.22)).interactive(), in: shape)
                        .overlay(shape.stroke(.white.opacity(0.46), lineWidth: 1))
                } else {
                    shape
                        .fill(.ultraThinMaterial.opacity(0.95))
                        .overlay(shape.stroke(.white.opacity(0.46), lineWidth: 1))
                }
            }
            .modifier(SoftGlassHoverModifier())
    }

    @ViewBuilder
    func liquidGlassButton(
        variant: LiquidGlassButtonVariant = .fullWidth,
        cornerRadius: CGFloat = 10,
        accentColor: Color = .white
    ) -> some View {
        switch variant {
        case .fullWidth:
            self
                .buttonStyle(SoftIOSButtonStyle())
                .liquidGlassControl(cornerRadius: cornerRadius, minHeight: 28, horizontalPadding: 0, accentColor: accentColor)

        case .pill:
            self
                .buttonStyle(SoftIOSButtonStyle())
                .liquidGlassPillButton(cornerRadius: cornerRadius)

        case .emphasizedPill:
            self
                .buttonStyle(SoftIOSButtonStyle())
                .liquidGlassPillButtonEmphasized(cornerRadius: cornerRadius)
        }
    }

    func liquidGlassInput(
        cornerRadius: CGFloat = 10,
        minHeight: CGFloat = 28,
        horizontalPadding: CGFloat = 11,
        accentColor: Color = .white
    ) -> some View {
        self.liquidGlassControl(cornerRadius: cornerRadius, minHeight: minHeight, horizontalPadding: horizontalPadding, accentColor: accentColor)
    }
}

// MARK: - Hover

private struct SoftGlassHoverModifier: ViewModifier {
    @State private var isHovered = false
    var enabled: Bool = true

    func body(content: Content) -> some View {
        content
            .scaleEffect(enabled && isHovered ? 1.007 : 1.0)
            .brightness(enabled && isHovered ? 0.012 : 0)
            .shadow(color: .white.opacity(enabled && isHovered ? 0.08 : 0), radius: 6, x: 0, y: 1)
            .onHover { hovering in
                guard enabled else { return }
                withAnimation(SoftIOSMotion.hover) {
                    isHovered = hovering
                }
            }
    }
}

// MARK: - Button Style

struct SoftIOSButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.983 : 1)
            .brightness(configuration.isPressed ? -0.02 : 0)
            .animation(SoftIOSMotion.press, value: configuration.isPressed)
    }
}

// MARK: - Focus Motion

private struct GlassFocusMotionModifier: ViewModifier {
    let isFocused: Bool
    let cornerRadius: CGFloat
    let accentColor: Color

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .scaleEffect(reduceMotion ? 1 : (isFocused ? 1.01 : 1))
            .shadow(
                color: accentColor.opacity(isFocused ? 0.20 : 0),
                radius: isFocused ? 10 : 0,
                y: 0
            )
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(accentColor.opacity(isFocused ? 0.55 : 0), lineWidth: 1.2)
                    .blur(radius: isFocused ? 2 : 0)
            }
            .animation(reduceMotion ? .none : SoftIOSMotion.state, value: isFocused)
    }
}

extension View {
    func liquidGlassFocusMotion(
        isFocused: Bool,
        cornerRadius: CGFloat = 10,
        accentColor: Color = .white
    ) -> some View {
        modifier(
            GlassFocusMotionModifier(
                isFocused: isFocused,
                cornerRadius: cornerRadius,
                accentColor: accentColor
            )
        )
    }
}
