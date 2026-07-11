import SwiftUI

enum Theme {
    enum Colors {
        static let background = Color(hex: "F7F7FB")
        static let surface = Color(hex: "FFFFFF")
        static let surface2 = Color(hex: "EEEFF2")
        static let label = Color(hex: "18191C")
        static let labelSecondary = Color(hex: "616265")
        static let labelTertiary = Color(hex: "8B8C8F")
        static let separator = Color(hex: "E3E4E7")
        static let borderStrong = Color(hex: "CACBCE")
        static let fieldBackground = Color(hex: "EEEFF2")
        static let tint = Color(hex: "3B82F6")
        static let tintHover = Color(hex: "2563EB")
        static let tintPressed = Color(hex: "1D4ED8")
        static let tintSoft = Color(hex: "DBEAFE")
        static let tintFaint = Color(hex: "EFF6FF")
        static let onTint = Color(hex: "FFFFFF")
        static let success = Color(hex: "62C58C")
        static let warning = Color(hex: "FF8947")
        static let danger = Color(hex: "F46C41")
        static let successSoft = Color(hex: "62C58C").opacity(0.14)
        static let dangerSoft = Color(hex: "F46C41").opacity(0.12)
    }

    enum Chart {
        static let recovery = Color(hex: "5DC0BA")
        static let calories = Color(hex: "FF8947")
        static let heartrate = Color(hex: "F46C41")
        static let sleep = Color(hex: "B182FE")
        static let activity = Color(hex: "62C58C")
        static let strain = Color(hex: "5A9CFF")
        static let protein = Color(hex: "5A9CFF")
        static let carbs = Color(hex: "FF8947")
        static let fat = Color(hex: "B182FE")

        /// A brighter partner of a metric hue, blended toward white for a gradient's highlight end.
        static func light(_ hue: Color) -> Color {
            hue.mix(with: .white, by: 0.28)
        }

        /// Ordered light→base stops for a metric's ring arc or sparkline fill.
        static func gradientStops(for hue: Color) -> [Color] {
            [light(hue), hue]
        }

        /// Angular gradient for a ring arc, sweeping light→base. Starts at −90° (12 o'clock) to match the ring.
        static func ringGradient(for hue: Color) -> AngularGradient {
            AngularGradient(
                colors: gradientStops(for: hue),
                center: .center,
                startAngle: .degrees(-90),
                endAngle: .degrees(270)
            )
        }

        /// Vertical area fill under a sparkline/line: the hue fading downward from ~0.18 opacity.
        static func areaGradient(for hue: Color) -> LinearGradient {
            LinearGradient(
                colors: [hue.opacity(0.18), hue.opacity(0.0)],
                startPoint: .top,
                endPoint: .bottom
            )
        }

        /// Faint full-circle track behind a ring arc, so the gradient arc reads as the figure.
        static func ringTrack(for hue: Color) -> Color {
            hue.opacity(0.12)
        }

        /// Vertical wash behind the recovery hero ring, by recovery band:
        /// >=67 cyan→mint, 34..<67 cyan→amber, <34 amber→coral.
        static func heroGradient(forRecovery pct: Double) -> LinearGradient {
            let stops: [Color]
            switch pct {
            case 67...: stops = [recovery, Theme.Colors.success]
            case 34 ..< 67: stops = [recovery, light(Theme.Colors.warning)]
            default: stops = [Theme.Colors.warning, light(Theme.Colors.danger)]
            }
            return LinearGradient(colors: stops, startPoint: .top, endPoint: .bottom)
        }

        /// Ghost ring track for the hero ring on the scenic backdrop (vs the on-white `ringTrack`).
        static let heroTrack = Color.white.opacity(0.18)

        /// Net-energy slider: deficit (red) → balanced (white) → surplus (blue). This data gradient is
        /// the only place chrome blue is allowed.
        static let netEnergyGradient = LinearGradient(
            colors: [Theme.Colors.danger, Theme.Colors.surface, Theme.Colors.tint],
            startPoint: .leading, endPoint: .trailing
        )

        /// Macro light→base gradient stops, reusing the existing macro hues.
        static var proteinGradient: [Color] { gradientStops(for: protein) }
        static var carbsGradient: [Color] { gradientStops(for: carbs) }
        static var fatGradient: [Color] { gradientStops(for: fat) }
    }

    enum Spacing {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 32
        static let xxxl: CGFloat = 48
    }

    enum Radius {
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let pill: CGFloat = 999
        static let card: CGFloat = 20
    }

    enum Font {
        static let largeTitle = SwiftUI.Font.system(.largeTitle, weight: .bold)
        static let title1 = SwiftUI.Font.system(.title, weight: .bold)
        static let title2 = SwiftUI.Font.system(.title2, weight: .semibold)
        static let body = SwiftUI.Font.system(.body, weight: .regular)
        static let bodyEmphasized = SwiftUI.Font.system(.body, weight: .semibold)
        static let callout = SwiftUI.Font.system(.callout, weight: .regular)
        static let subhead = SwiftUI.Font.system(.subheadline, weight: .regular)
        static let footnote = SwiftUI.Font.system(.footnote, weight: .regular)

        /// Small uppercase header above cards and form fields. Caption-sized, semibold; the
        /// `Txt(.sectionHeader)` variant adds the letter-tracking and uppercasing.
        static let sectionHeader = SwiftUI.Font.system(.caption, weight: .semibold)

        /// SF Rounded, monospaced-digit number at an arbitrary size/weight. Base for the ramp below.
        static func number(size: CGFloat, weight: SwiftUI.Font.Weight = .semibold) -> SwiftUI.Font {
            .system(size: size, weight: weight, design: .rounded).monospacedDigit()
        }

        /// Centerpiece number, e.g. a hero ring's center. 44pt.
        static let heroNumber = number(size: 44, weight: .semibold)
        /// A card's headline number when it isn't the screen hero. 34pt.
        static let metricNumber = number(size: 34, weight: .bold)
        /// Medium metric, e.g. a stat row's value. 22pt.
        static let statNumber = number(size: 22, weight: .semibold)
        /// Inline numeric value in body copy. 17pt.
        static let inlineNumber = number(size: 17, weight: .semibold)

        /// Onboarding hero title (system, not serif); the single non-ramp title size.
        static let onboardingTitle = SwiftUI.Font.system(size: 32, weight: .semibold)
    }

    enum Shadow {
        struct Style {
            let color: Color
            let radius: CGFloat
            let x: CGFloat
            let y: CGFloat
        }
        /// Default resting card shadow: low and tight.
        static let card = Style(color: Color.black.opacity(0.05), radius: 12, x: 0, y: 4)
        /// Emphasized / hero card shadow: floats slightly more.
        static let cardElevated = Style(color: Color.black.opacity(0.06), radius: 20, x: 0, y: 8)
        /// Raised chrome (the center FAB): tinted, directional.
        static func tinted(_ color: Color) -> Style {
            Style(color: color.opacity(0.35), radius: 12, x: 0, y: 6)
        }
    }

    enum Material {
        /// Chrome blur used as the pre-iOS-26 fallback for Liquid Glass on the tab bar / FAB.
        static let chromeFallback: SwiftUI.Material = .bar
        /// Translucent material for a nested inset panel. Cards themselves stay opaque.
        static let panel: SwiftUI.Material = .regularMaterial
    }

    enum Motion {
        /// Looping shimmer for skeleton / loading states.
        static let shimmer = SwiftUI.Animation.linear(duration: 1.1).repeatForever(autoreverses: false)
        /// One spring reused for onboarding step pushes + stepper count-ups.
        static let stepTransition = SwiftUI.Animation.spring(response: 0.42, dampingFraction: 0.85)
    }

    enum Heatmap {
        /// Recovery % → cell color: the recovery hue at graded opacity by band.
        static func recoveryRamp(_ pct: Double) -> Color {
            let opacity: Double
            switch pct {
            case 67...: opacity = 1.0
            case 50 ..< 67: opacity = 0.85
            case 34 ..< 50: opacity = 0.55
            default: opacity = 0.25
            }
            return Theme.Chart.recovery.opacity(opacity)
        }
    }

    enum Layout {
        /// Leading inset for hairline dividers in settings / list rows (icon tile width + gaps).
        static let settingsRowInset: CGFloat = Theme.Spacing.lg + 30 + Theme.Spacing.md
    }
}

extension Color {
    init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        var value: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&value)
        let r = Double((value >> 16) & 0xFF) / 255
        let g = Double((value >> 8) & 0xFF) / 255
        let b = Double(value & 0xFF) / 255
        self.init(.sRGB, red: r, green: g, blue: b, opacity: 1)
    }
}

extension View {
    /// Applies a named card shadow (`.card` resting, `.cardElevated` hero) from `Theme.Shadow`.
    func cardShadow(_ style: Theme.Shadow.Style = Theme.Shadow.card) -> some View {
        shadow(color: style.color, radius: style.radius, x: style.x, y: style.y)
    }

    /// Liquid Glass for navigation chrome only (tab bar, FAB, toolbars), never a data card.
    /// iOS 26+ uses real `.glassEffect`; earlier targets fall back to a chrome material + hairline.
    /// `tint` is the FAB's blue; `interactive` is FAB-only.
    @ViewBuilder
    func gainsGlassChrome(
        in shape: some Shape,
        tint: Color? = nil,
        interactive: Bool = false
    ) -> some View {
        if #available(iOS 26.0, *) {
            glassEffect(Glass.gainsChrome(tint: tint, interactive: interactive), in: shape)
        } else {
            background(Theme.Material.chromeFallback, in: shape)
                .overlay { shape.stroke(Color.black.opacity(0.06), lineWidth: 1) }
        }
    }
}

@available(iOS 26.0, *)
extension Glass {
    /// Chrome glass recipe: regular Liquid Glass, optionally blue-tinted and/or interactive (both FAB-only).
    static func gainsChrome(tint: Color?, interactive: Bool) -> Glass {
        var effect = Glass.regular
        if let tint { effect = effect.tint(tint) }
        if interactive { effect = effect.interactive() }
        return effect
    }
}
