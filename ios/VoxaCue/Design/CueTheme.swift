import SwiftUI
import UIKit

enum CueTheme {
    static let canvas = Color("BrandBackground")
    static let surface = Color("BrandSurface")
    static let ink = Color.cueAdaptive(
        light: UIColor(red: 7 / 255, green: 17 / 255, blue: 34 / 255, alpha: 1),
        dark: UIColor(red: 244 / 255, green: 247 / 255, blue: 252 / 255, alpha: 1)
    )
    static let secondaryInk = Color.cueAdaptive(
        light: UIColor(red: 77 / 255, green: 91 / 255, blue: 115 / 255, alpha: 1),
        dark: UIColor(red: 174 / 255, green: 186 / 255, blue: 205 / 255, alpha: 1)
    )
    static let border = Color.cueAdaptive(
        light: UIColor(red: 211 / 255, green: 219 / 255, blue: 235 / 255, alpha: 1),
        dark: UIColor(red: 42 / 255, green: 59 / 255, blue: 86 / 255, alpha: 1)
    )
    static let indigo = Color(red: 103 / 255, green: 101 / 255, blue: 1)
    static let periwinkle = Color(red: 139 / 255, green: 139 / 255, blue: 1)
    static let violet = Color("AccentColor")
    static let violetSoft = Color.cueAdaptive(
        light: UIColor(red: 231 / 255, green: 230 / 255, blue: 1, alpha: 1),
        dark: UIColor(red: 42 / 255, green: 43 / 255, blue: 91 / 255, alpha: 1)
    )
    static let green = Color.cueAdaptive(
        light: UIColor(red: 20 / 255, green: 132 / 255, blue: 87 / 255, alpha: 1),
        dark: UIColor(red: 83 / 255, green: 218 / 255, blue: 160 / 255, alpha: 1)
    )
    static let greenBright = Color(red: 61 / 255, green: 199 / 255, blue: 136 / 255)
    static let navy = Color.cueAdaptive(
        light: UIColor(red: 7 / 255, green: 17 / 255, blue: 34 / 255, alpha: 1),
        dark: UIColor(red: 18 / 255, green: 31 / 255, blue: 52 / 255, alpha: 1)
    )
    static let amber = Color.cueAdaptive(
        light: UIColor(red: 174 / 255, green: 104 / 255, blue: 22 / 255, alpha: 1),
        dark: UIColor(red: 245 / 255, green: 177 / 255, blue: 82 / 255, alpha: 1)
    )
    static let red = Color.cueAdaptive(
        light: UIColor(red: 177 / 255, green: 48 / 255, blue: 61 / 255, alpha: 1),
        dark: UIColor(red: 255 / 255, green: 112 / 255, blue: 124 / 255, alpha: 1)
    )

    static let signalGradient = LinearGradient(
        colors: [indigo, violet],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    enum Radius {
        static let small: CGFloat = 12
        static let medium: CGFloat = 18
        static let large: CGFloat = 26
        static let pill: CGFloat = 999
    }

    enum Space {
        static let xSmall: CGFloat = 6
        static let small: CGFloat = 10
        static let medium: CGFloat = 16
        static let large: CGFloat = 20
        static let xLarge: CGFloat = 28
        static let hero: CGFloat = 40
    }
}

private extension Color {
    static func cueAdaptive(light: UIColor, dark: UIColor) -> Color {
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? dark : light
        })
    }
}

extension Font {
    static let cueHero = Font.system(.largeTitle, design: .rounded, weight: .light)
    static let cueTitle = Font.system(.title, design: .rounded, weight: .semibold)
    static let cueSection = Font.system(.title3, design: .rounded, weight: .semibold)
    static let cueMetric = Font.system(.title, design: .rounded, weight: .light).monospacedDigit()
    static let cueBody = Font.system(.body, design: .rounded, weight: .regular)
    static let cueCaption = Font.system(.caption, design: .rounded, weight: .medium)
}

enum CueMotion {
    static func quick(reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : .spring(response: 0.30, dampingFraction: 0.82)
    }

    static func settle(reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : .spring(response: 0.52, dampingFraction: 0.88)
    }
}

struct SpringPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.975 : 1)
            .opacity(configuration.isPressed ? 0.86 : 1)
            .animation(CueMotion.quick(reduceMotion: reduceMotion), value: configuration.isPressed)
    }
}

struct PremiumCard<Content: View>: View {
    let padding: CGFloat
    @ViewBuilder let content: Content

    init(padding: CGFloat, @ViewBuilder content: () -> Content) {
        self.padding = padding
        self.content = content()
    }

    var body: some View {
        content
            .padding(padding)
            .background {
                RoundedRectangle(cornerRadius: CueTheme.Radius.large, style: .continuous)
                    .fill(CueTheme.surface)
                    .overlay {
                        LinearGradient(
                            colors: [Color.white.opacity(0.10), CueTheme.periwinkle.opacity(0.025)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                        .clipShape(RoundedRectangle(cornerRadius: CueTheme.Radius.large, style: .continuous))
                    }
            }
            .overlay {
                RoundedRectangle(cornerRadius: CueTheme.Radius.large, style: .continuous)
                    .stroke(CueTheme.border.opacity(0.72), lineWidth: 0.75)
            }
            .shadow(color: CueTheme.navy.opacity(0.075), radius: 24, x: 0, y: 12)
    }
}

struct VoxaButton: View {
    enum Style {
        case primary
        case secondary
        case destructive
    }

    let title: String
    let symbol: String
    let style: Style
    let disabled: Bool
    let action: () -> Void
    @State private var feedbackTrigger = 0

    init(title: String, symbol: String, style: Style, disabled: Bool, action: @escaping () -> Void) {
        self.title = title
        self.symbol = symbol
        self.style = style
        self.disabled = disabled
        self.action = action
    }

    var body: some View {
        Button {
            feedbackTrigger += 1
            action()
        } label: {
            HStack(spacing: 12) {
                Text(title)
                    .font(.system(.body, design: .rounded, weight: .semibold))
                Spacer(minLength: 8)
                Image(systemName: symbol)
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 36, height: 36)
                    .background(foreground.opacity(0.12))
                    .clipShape(Circle())
            }
            .foregroundStyle(foreground)
            .padding(.leading, 21)
            .padding(.trailing, 8)
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(background)
            .clipShape(Capsule())
            .overlay {
                Capsule()
                    .stroke(Color.white.opacity(style == .primary ? 0.12 : 0), lineWidth: 0.75)
            }
            .shadow(
                color: style == .primary ? CueTheme.indigo.opacity(0.20) : .clear,
                radius: 14,
                x: 0,
                y: 8
            )
            .opacity(disabled ? 0.45 : 1)
            .contentShape(Capsule())
        }
        .buttonStyle(SpringPressStyle())
        .disabled(disabled)
        .sensoryFeedback(.impact(weight: .light, intensity: 0.7), trigger: feedbackTrigger)
    }

    private var background: AnyShapeStyle {
        switch style {
        case .primary: AnyShapeStyle(CueTheme.signalGradient)
        case .secondary: AnyShapeStyle(CueTheme.violetSoft)
        case .destructive: AnyShapeStyle(CueTheme.red)
        }
    }

    private var foreground: Color {
        switch style {
        case .primary, .destructive: .white
        case .secondary: CueTheme.violet
        }
    }
}

struct VoxaAsyncButton: View {
    let title: String
    let loadingTitle: String
    let symbol: String
    let isLoading: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.white)
                } else {
                    Image(systemName: symbol)
                }
                Text(isLoading ? loadingTitle : title)
                    .font(.system(.body, design: .rounded, weight: .semibold))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 54)
            .background(CueTheme.signalGradient)
            .clipShape(Capsule())
            .shadow(color: CueTheme.indigo.opacity(0.20), radius: 14, y: 8)
        }
        .buttonStyle(SpringPressStyle())
        .disabled(isLoading)
        .accessibilityLabel(isLoading ? loadingTitle : title)
    }
}

struct StatusPill: View {
    let label: String
    let symbol: String
    let color: Color

    init(label: String, symbol: String, color: Color) {
        self.label = label
        self.symbol = symbol
        self.color = color
    }

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .semibold))
            Text(label)
                .font(.cueCaption)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .foregroundStyle(color)
        .padding(.horizontal, 11)
        .padding(.vertical, 7)
        .background(color.opacity(0.11))
        .clipShape(Capsule())
        .overlay { Capsule().stroke(color.opacity(0.16), lineWidth: 0.5) }
        .accessibilityElement(children: .combine)
    }
}

struct MetricTile: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let label: String
    let value: String
    let detail: String
    let tint: Color

    init(label: String, value: String, detail: String, tint: Color) {
        self.label = label
        self.value = value
        self.detail = detail
        self.tint = tint
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            CueSectionLabel(text: label, color: CueTheme.secondaryInk)
            Text(value)
                .font(.cueMetric)
                .foregroundStyle(CueTheme.ink)
                .contentTransition(reduceMotion ? .identity : .numericText())
                .minimumScaleFactor(0.75)
            Text(detail)
                .font(.cueCaption)
                .foregroundStyle(tint)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: 108, alignment: .leading)
        .padding(16)
        .background(CueTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: CueTheme.Radius.medium, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: CueTheme.Radius.medium, style: .continuous)
                .stroke(CueTheme.border.opacity(0.62), lineWidth: 0.7)
        }
        .overlay(alignment: .bottom) {
            Capsule()
                .fill(tint.opacity(0.42))
                .frame(height: 3)
                .padding(.horizontal, 14)
                .padding(.bottom, 7)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue("\(value), \(detail)")
    }
}

struct CueMetricGrid<Content: View>: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let spacing: CGFloat
    @ViewBuilder let content: Content

    init(spacing: CGFloat, @ViewBuilder content: () -> Content) {
        self.spacing = spacing
        self.content = content()
    }

    var body: some View {
        LazyVGrid(columns: columns, spacing: spacing) {
            content
        }
    }

    private var columns: [GridItem] {
        dynamicTypeSize.isAccessibilitySize
            ? [GridItem(.flexible())]
            : [GridItem(.flexible()), GridItem(.flexible())]
    }
}

struct CueWordmark: View {
    let compact: Bool

    init(compact: Bool) {
        self.compact = compact
    }

    var body: some View {
        HStack(spacing: compact ? 8 : 11) {
            ZStack {
                ForEach(0..<3, id: \.self) { index in
                    Circle()
                        .stroke(CueTheme.periwinkle.opacity(0.95 - (Double(index) * 0.22)), lineWidth: 1.4)
                        .frame(
                            width: (compact ? 10 : 13) + CGFloat(index * (compact ? 7 : 9)),
                            height: (compact ? 10 : 13) + CGFloat(index * (compact ? 7 : 9))
                        )
                }
                Circle()
                    .fill(CueTheme.signalGradient)
                    .frame(width: compact ? 7 : 9, height: compact ? 7 : 9)
            }
            .frame(width: compact ? 31 : 40, height: compact ? 31 : 40)

            HStack(alignment: .firstTextBaseline, spacing: compact ? 5 : 7) {
                Text("Voxa")
                    .font(.system(size: compact ? 20 : 28, weight: .light, design: .rounded))
                    .foregroundStyle(CueTheme.ink)
                Text("CUE")
                    .font(.system(size: compact ? 8 : 9, weight: .bold, design: .rounded))
                    .tracking(1.2)
                    .foregroundStyle(CueTheme.violet)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Voxa Cue")
    }
}

struct CuePulseGlyph: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isPulsing = false

    let symbol: String
    let size: CGFloat
    let animated: Bool

    var body: some View {
        ZStack {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .stroke(CueTheme.periwinkle.opacity(0.52 - (Double(index) * 0.12)), lineWidth: 1.25)
                    .frame(
                        width: size * (0.46 + (Double(index) * 0.20)),
                        height: size * (0.46 + (Double(index) * 0.20))
                    )
                    .scaleEffect(isPulsing && index == 2 ? 1.06 : 1)
                    .opacity(isPulsing && index == 2 ? 0.55 : 1)
            }
            Circle()
                .fill(CueTheme.signalGradient)
                .frame(width: size * 0.38, height: size * 0.38)
                .shadow(color: CueTheme.indigo.opacity(0.28), radius: 14)
            Image(systemName: symbol)
                .font(.system(size: size * 0.16, weight: .medium))
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
        .onAppear {
            guard animated, !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) {
                isPulsing = true
            }
        }
        .accessibilityHidden(true)
    }
}

struct CueSectionLabel: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text.uppercased())
            .font(.system(.caption2, design: .rounded, weight: .bold))
            .tracking(1.15)
            .foregroundStyle(color)
    }
}

struct ScreenTitle: View {
    let eyebrow: String
    let title: String
    let subtitle: String

    init(eyebrow: String, title: String, subtitle: String) {
        self.eyebrow = eyebrow
        self.title = title
        self.subtitle = subtitle
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            CueSectionLabel(text: eyebrow, color: CueTheme.violet)
            Text(title)
                .font(.cueTitle)
                .foregroundStyle(CueTheme.ink)
                .fixedSize(horizontal: false, vertical: true)
            Text(subtitle)
                .font(.cueBody)
                .foregroundStyle(CueTheme.secondaryInk)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
