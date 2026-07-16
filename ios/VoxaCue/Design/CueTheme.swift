import SwiftUI

enum CueTheme {
    static let canvas = Color("BrandBackground")
    static let surface = Color("BrandSurface")
    static let ink = Color(red: 0.094, green: 0.098, blue: 0.094)
    static let secondaryInk = Color(red: 0.408, green: 0.384, blue: 0.369)
    static let border = Color(red: 0.886, green: 0.867, blue: 0.855)
    static let violet = Color("AccentColor")
    static let violetSoft = Color(red: 0.900, green: 0.864, blue: 0.957)
    static let green = Color(red: 0.094, green: 0.471, blue: 0.267)
    static let greenBright = Color(red: 0.263, green: 0.722, blue: 0.416)
    static let navy = Color(red: 0.071, green: 0.102, blue: 0.149)
    static let amber = Color(red: 0.749, green: 0.431, blue: 0.153)
    static let red = Color(red: 0.710, green: 0.216, blue: 0.216)

    enum Radius {
        static let small: CGFloat = 12
        static let medium: CGFloat = 18
        static let large: CGFloat = 24
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

extension Font {
    static let cueHero = Font.system(size: 44, weight: .light, design: .rounded)
    static let cueTitle = Font.system(size: 30, weight: .semibold, design: .rounded)
    static let cueSection = Font.system(size: 20, weight: .semibold, design: .rounded)
    static let cueMetric = Font.system(size: 32, weight: .light, design: .rounded).monospacedDigit()
    static let cueBody = Font.system(size: 16, weight: .regular, design: .rounded)
    static let cueCaption = Font.system(size: 12, weight: .medium, design: .rounded)
}

struct SpringPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.975 : 1)
            .opacity(configuration.isPressed ? 0.88 : 1)
            .animation(.spring(response: 0.32, dampingFraction: 0.72), value: configuration.isPressed)
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
            .background(CueTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: CueTheme.Radius.medium, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: CueTheme.Radius.medium, style: .continuous)
                    .stroke(CueTheme.border.opacity(0.72), lineWidth: 0.7)
            }
            .padding(3)
            .background(CueTheme.ink.opacity(0.035))
            .clipShape(RoundedRectangle(cornerRadius: CueTheme.Radius.large, style: .continuous))
            .shadow(color: CueTheme.navy.opacity(0.055), radius: 22, x: 0, y: 10)
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

    init(title: String, symbol: String, style: Style, disabled: Bool, action: @escaping () -> Void) {
        self.title = title
        self.symbol = symbol
        self.style = style
        self.disabled = disabled
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                Spacer(minLength: 8)
                Image(systemName: symbol)
                    .font(.system(size: 14, weight: .medium))
                    .frame(width: 34, height: 34)
                    .background(foreground.opacity(0.10))
                    .clipShape(Circle())
            }
            .foregroundStyle(foreground)
            .padding(.leading, 20)
            .padding(.trailing, 8)
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(background)
            .clipShape(Capsule())
            .opacity(disabled ? 0.42 : 1)
        }
        .buttonStyle(SpringPressStyle())
        .disabled(disabled)
    }

    private var background: Color {
        switch style {
        case .primary: CueTheme.navy
        case .secondary: CueTheme.violetSoft
        case .destructive: CueTheme.red
        }
    }

    private var foreground: Color {
        switch style {
        case .primary, .destructive: .white
        case .secondary: CueTheme.violet
        }
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
        }
        .foregroundStyle(color)
        .padding(.horizontal, 11)
        .padding(.vertical, 7)
        .background(color.opacity(0.10))
        .clipShape(Capsule())
        .accessibilityElement(children: .combine)
    }
}

struct MetricTile: View {
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
            Text(label.uppercased())
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .tracking(1.1)
                .foregroundStyle(CueTheme.secondaryInk)
            Text(value)
                .font(.cueMetric)
                .foregroundStyle(CueTheme.ink)
                .contentTransition(.numericText())
            Text(detail)
                .font(.cueCaption)
                .foregroundStyle(tint)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(CueTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: CueTheme.Radius.medium, style: .continuous))
        .overlay(alignment: .bottom) {
            Capsule()
                .fill(tint.opacity(0.38))
                .frame(height: 3)
                .padding(.horizontal, 14)
                .padding(.bottom, 7)
        }
    }
}

struct CueWordmark: View {
    let compact: Bool

    init(compact: Bool) {
        self.compact = compact
    }

    var body: some View {
        HStack(spacing: compact ? 8 : 12) {
            ZStack {
                Capsule()
                    .fill(CueTheme.navy)
                    .frame(width: compact ? 34 : 44, height: compact ? 24 : 30)
                Circle()
                    .stroke(CueTheme.violetSoft, lineWidth: 1.4)
                    .frame(width: compact ? 13 : 17, height: compact ? 13 : 17)
            }
            Text("Cue")
                .font(.system(size: compact ? 20 : 28, weight: .light, design: .rounded))
                .foregroundStyle(CueTheme.ink)
        }
        .accessibilityLabel("Voxa Cue")
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
            Text(eyebrow.uppercased())
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .tracking(1.5)
                .foregroundStyle(CueTheme.violet)
            Text(title)
                .font(.cueTitle)
                .foregroundStyle(CueTheme.ink)
            Text(subtitle)
                .font(.cueBody)
                .foregroundStyle(CueTheme.secondaryInk)
                .lineSpacing(3)
        }
    }
}
