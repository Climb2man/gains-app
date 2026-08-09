import SwiftUI

enum Theme {
    /// DARK ONLY. The app pins `.preferredColorScheme(.dark)` at the root, so these are absolute
    /// values rather than per-scheme pairs and there is no light variant to keep in step.
    ///
    /// Direction: WHOOP's colour personality. A near-black ground, almost no chrome, and vivid
    /// accents that carry meaning rather than decorate. The greens and yellows below are electric
    /// on purpose — they are unreadable on white, which is precisely why this is not a theme that
    /// could be flipped to light without redesigning it.
    enum Colors {
        /// Not pure black: a faint blue cast keeps the surfaces above it from looking like haze.
        static let background = Color(hex: "08090B")
        static let surface = Color(hex: "121317")
        static let surface2 = Color(hex: "1B1D22")
        static let label = Color(hex: "F5F6F8")
        static let labelSecondary = Color(hex: "A0A4AD")
        static let labelTertiary = Color(hex: "6E727B")
        static let separator = Color(hex: "24262C")
        static let borderStrong = Color(hex: "34373E")
        static let fieldBackground = Color(hex: "1B1D22")

        /// WHOOP's strain blue, used as the app's chrome accent.
        static let tint = Color(hex: "0093E7")
        static let tintHover = Color(hex: "2AA8EC")
        static let tintPressed = Color(hex: "47B6F0")
        static let tintSoft = Color(hex: "0093E7").opacity(0.20)
        static let tintFaint = Color(hex: "0093E7").opacity(0.09)
        /// Deep navy rather than white: white text on the strain blue vibrates badly.
        static let onTint = Color(hex: "05161F")

        /// The recovery triad. Used for state throughout the app, not only for recovery — a red
        /// warning and a red recovery are the same red on purpose, so the vocabulary stays small.
        static let success = Color(hex: "16EC06")
        static let warning = Color(hex: "FFDE00")
        static let danger = Color(hex: "FF0026")
        static let successSoft = success.opacity(0.16)
        static let dangerSoft = danger.opacity(0.14)
    }

    enum Chart {
        /// Recovery green — WHOOP's primary identity colour.
        static let recovery = Theme.Colors.success
        static let calories = Color(hex: "FF8A3D")
        static let heartrate = Theme.Colors.danger
        static let sleep = Color(hex: "9C8BFF")
        static let activity = Color(hex: "16EC06")
        static let strain = Theme.Colors.tint
        static let protein = Theme.Colors.tint
        static let carbs = Color(hex: "FF8A3D")
        static let fat = Color(hex: "9C8BFF")

        /// Recovery % → its band colour, on WHOOP's own thresholds: green ≥67, yellow 34–66,
        /// red below. This is the one idea worth copying wholesale — in WHOOP the number is not
        /// merely tinted, the colour IS the reading, and it is legible before the digits are.
        static func recoveryBand(_ pct: Double) -> Color {
            switch pct {
            case 67...: return Theme.Colors.success
            case 34 ..< 67: return Theme.Colors.warning
            default: return Theme.Colors.danger
            }
        }

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

        /// Vertical wash behind the recovery hero ring, taken from the band colour so the backdrop
        /// and the ring agree. Deliberately a single hue fading into itself rather than a two-colour
        /// blend: on a near-black ground a gradient between two vivid hues reads as a smear.
        static func heroGradient(forRecovery pct: Double) -> LinearGradient {
            let band = recoveryBand(pct)
            return LinearGradient(
                colors: [band.opacity(0.55), band.opacity(0.06)],
                startPoint: .top, endPoint: .bottom
            )
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

        // The ramp runs larger and heavier than a stock iOS scale. In WHOOP the reading is the
        // interface — the number arrives before any label does — and a dark ground carries big
        // type without the page feeling shouty the way a light one would.

        /// Centerpiece number, e.g. a hero ring's center.
        static let heroNumber = number(size: 54, weight: .bold)
        /// A card's headline number when it isn't the screen hero.
        static let metricNumber = number(size: 40, weight: .bold)
        /// Medium metric, e.g. a stat row's value.
        static let statNumber = number(size: 25, weight: .semibold)
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
        /// On a near-black ground a black drop shadow is invisible, so elevation is carried by the
        /// surface being lighter than the background, not by a shadow. These stay defined (call
        /// sites expect them) but are dialled almost to nothing — WHOOP's surfaces are flat, and a
        /// fake glow around every card is the fastest way to make a dark theme look cheap.
        static let card = Style(color: Color.black.opacity(0.35), radius: 10, x: 0, y: 3)
        /// Emphasized / hero card: a touch more separation, still no glow.
        static let cardElevated = Style(color: Color.black.opacity(0.45), radius: 18, x: 0, y: 6)
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
        /// Recovery % → cell colour. Now the BAND colour rather than one hue at graded opacity:
        /// a green calendar shaded lighter and darker asks the reader to judge luminance, where
        /// green/yellow/red is legible at a glance and matches what WHOOP itself shows.
        /// Opacity still varies within a band so a run of similar days keeps some texture.
        static func recoveryRamp(_ pct: Double) -> Color {
            let opacity: Double
            switch pct {
            case 84...: opacity = 1.0
            case 67 ..< 84: opacity = 0.82
            case 50 ..< 67: opacity = 0.92
            case 34 ..< 50: opacity = 0.72
            default: opacity = 0.85
            }
            return Theme.Chart.recoveryBand(pct).opacity(opacity)
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
            // Hairline is white-on-dark: the previous black stroke was invisible against the
            // near-black ground, leaving the pre-iOS-26 tab bar with no edge at all.
            background(Theme.Material.chromeFallback, in: shape)
                .overlay { shape.stroke(Color.white.opacity(0.10), lineWidth: 1) }
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
