import SwiftUI
import UIKit

enum CueTheme {
    static let canvas = Color("BrandBackground")
    static let surface = Color("BrandSurface")
    static let ink = Color.cueAdaptive(
        light: UIColor(red: 11 / 255, green: 23 / 255, blue: 27 / 255, alpha: 1),
        dark: UIColor(red: 239 / 255, green: 247 / 255, blue: 244 / 255, alpha: 1)
    )
    static let secondaryInk = Color.cueAdaptive(
        light: UIColor(red: 83 / 255, green: 99 / 255, blue: 103 / 255, alpha: 1),
        dark: UIColor(red: 169 / 255, green: 187 / 255, blue: 184 / 255, alpha: 1)
    )
    static let border = Color.cueAdaptive(
        light: UIColor(red: 216 / 255, green: 223 / 255, blue: 219 / 255, alpha: 1),
        dark: UIColor(red: 47 / 255, green: 68 / 255, blue: 68 / 255, alpha: 1)
    )
    static let signalBright = Color(red: 52 / 255, green: 184 / 255, blue: 170 / 255)
    static let signal = Color.cueAdaptive(
        light: UIColor(red: 11 / 255, green: 117 / 255, blue: 111 / 255, alpha: 1),
        dark: UIColor(red: 83 / 255, green: 210 / 255, blue: 195 / 255, alpha: 1)
    )
    static let signalSoft = Color.cueAdaptive(
        light: UIColor(red: 224 / 255, green: 239 / 255, blue: 235 / 255, alpha: 1),
        dark: UIColor(red: 18 / 255, green: 58 / 255, blue: 57 / 255, alpha: 1)
    )
    static let haptic = Color.cueAdaptive(
        light: UIColor(red: 145 / 255, green: 75 / 255, blue: 25 / 255, alpha: 1),
        dark: UIColor(red: 241 / 255, green: 164 / 255, blue: 95 / 255, alpha: 1)
    )
    static let green = Color.cueAdaptive(
        light: UIColor(red: 13 / 255, green: 116 / 255, blue: 74 / 255, alpha: 1),
        dark: UIColor(red: 83 / 255, green: 218 / 255, blue: 160 / 255, alpha: 1)
    )
    static let greenBright = Color(red: 61 / 255, green: 199 / 255, blue: 136 / 255)
    static let navy = Color.cueAdaptive(
        light: UIColor(red: 11 / 255, green: 23 / 255, blue: 27 / 255, alpha: 1),
        dark: UIColor(red: 8 / 255, green: 18 / 255, blue: 22 / 255, alpha: 1)
    )
    static let amber = Color.cueAdaptive(
        light: UIColor(red: 140 / 255, green: 81 / 255, blue: 12 / 255, alpha: 1),
        dark: UIColor(red: 245 / 255, green: 177 / 255, blue: 82 / 255, alpha: 1)
    )
    static let red = Color.cueAdaptive(
        light: UIColor(red: 177 / 255, green: 48 / 255, blue: 61 / 255, alpha: 1),
        dark: UIColor(red: 255 / 255, green: 112 / 255, blue: 124 / 255, alpha: 1)
    )

    static let actionFill = Color(red: 8 / 255, green: 91 / 255, blue: 86 / 255)

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
    static let cueBody = Font.system(.body, design: .default, weight: .regular)
    static let cueCaption = Font.system(.caption, design: .default, weight: .medium)
}

enum CueMotion {
    static func quick(reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : .spring(response: 0.30, dampingFraction: 0.82)
    }

    static func settle(reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : .spring(response: 0.52, dampingFraction: 0.88)
    }

    static func breathe(reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : .smooth(duration: 1.8).repeatForever(autoreverses: true)
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
            }
            .overlay {
                RoundedRectangle(cornerRadius: CueTheme.Radius.large, style: .continuous)
                    .stroke(CueTheme.border.opacity(0.68), lineWidth: 0.6)
            }
            .shadow(color: CueTheme.navy.opacity(0.045), radius: 9, x: 0, y: 3)
    }
}

struct HeroCard<Content: View>: View {
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
            }
            .overlay {
                RoundedRectangle(cornerRadius: CueTheme.Radius.large, style: .continuous)
                    .stroke(CueTheme.signal.opacity(0.16), lineWidth: 0.75)
            }
            .shadow(color: CueTheme.navy.opacity(0.09), radius: 20, x: 0, y: 9)
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
                color: style == .primary ? CueTheme.navy.opacity(0.14) : .clear,
                radius: 12,
                x: 0,
                y: 6
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
        case .primary: AnyShapeStyle(CueTheme.actionFill)
        case .secondary: AnyShapeStyle(CueTheme.signalSoft)
        case .destructive: AnyShapeStyle(CueTheme.red)
        }
    }

    private var foreground: Color {
        switch style {
        case .primary, .destructive: .white
        case .secondary: CueTheme.signal
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
            .background(CueTheme.actionFill)
            .clipShape(Capsule())
            .shadow(color: CueTheme.navy.opacity(0.14), radius: 12, y: 6)
        }
        .buttonStyle(SpringPressStyle())
        .disabled(isLoading)
        .accessibilityLabel(isLoading ? loadingTitle : title)
    }
}

struct StatusPill: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

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
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                .minimumScaleFactor(dynamicTypeSize.isAccessibilitySize ? 1 : 0.85)
        }
        .foregroundStyle(color)
        .padding(.horizontal, 11)
        .padding(.vertical, 7)
        .background(color.opacity(0.11))
        .clipShape(RoundedRectangle(cornerRadius: dynamicTypeSize.isAccessibilitySize ? 14 : CueTheme.Radius.pill))
        .overlay {
            RoundedRectangle(cornerRadius: dynamicTypeSize.isAccessibilitySize ? 14 : CueTheme.Radius.pill)
                .stroke(color.opacity(0.16), lineWidth: 0.5)
        }
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
                Circle()
                    .trim(from: 0.10, to: 0.90)
                    .stroke(
                        CueTheme.ink,
                        style: StrokeStyle(lineWidth: compact ? 2.2 : 2.8, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-35))
                    .padding(compact ? 3 : 4)
                Image(systemName: "waveform.path")
                    .font(.system(size: compact ? 11 : 15, weight: .medium))
                    .foregroundStyle(CueTheme.ink)
                Circle()
                    .fill(CueTheme.actionFill)
                    .frame(width: compact ? 5 : 7, height: compact ? 5 : 7)
                    .offset(x: compact ? 11 : 14)
            }
            .frame(width: compact ? 31 : 40, height: compact ? 31 : 40)

            HStack(alignment: .firstTextBaseline, spacing: compact ? 4 : 5) {
                Text("Voxa")
                    .font(.system(size: compact ? 20 : 28, weight: .light, design: .rounded))
                    .foregroundStyle(CueTheme.ink)
                Text("Cue")
                    .font(.system(size: compact ? 20 : 28, weight: .medium, design: .rounded))
                    .foregroundStyle(CueTheme.signal)
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
            ForEach(0..<2, id: \.self) { index in
                Circle()
                    .stroke(CueTheme.signalBright.opacity(0.50 - (Double(index) * 0.14)), lineWidth: 1.25)
                    .frame(
                        width: size * (0.54 + (Double(index) * 0.23)),
                        height: size * (0.54 + (Double(index) * 0.23))
                    )
                    .scaleEffect(isPulsing && index == 1 ? 1.04 : 1)
                    .opacity(isPulsing && index == 1 ? 0.62 : 1)
            }
            Circle()
                .fill(CueTheme.actionFill)
                .frame(width: size * 0.38, height: size * 0.38)
            Image(systemName: symbol)
                .font(.system(size: size * 0.16, weight: .medium))
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
        .onAppear {
            guard animated, !reduceMotion else { return }
            withAnimation(CueMotion.breathe(reduceMotion: reduceMotion)) {
                isPulsing = true
            }
        }
        .onChange(of: reduceMotion) { _, shouldReduceMotion in
            if shouldReduceMotion {
                isPulsing = false
            } else if animated {
                withAnimation(CueMotion.breathe(reduceMotion: false)) {
                    isPulsing = true
                }
            }
        }
        .accessibilityHidden(true)
    }
}

struct SectionMark: View {
    let assetName: String
    let size: CGFloat

    init(assetName: String, size: CGFloat) {
        self.assetName = assetName
        self.size = size
    }

    var body: some View {
        Image(assetName)
            .resizable()
            .interpolation(.high)
            .antialiased(true)
            .scaledToFit()
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

struct CueSectionLabel: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.system(.caption, design: .default, weight: .semibold))
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
            CueSectionLabel(text: eyebrow, color: CueTheme.signal)
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
