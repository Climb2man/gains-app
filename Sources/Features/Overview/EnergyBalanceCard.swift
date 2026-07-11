import SwiftUI

struct EnergyBalanceCard: View {
    /// The selected day's eaten-calorie totals (calories in).
    let totals: DailyTotals
    /// The selected day's Whoop snapshot; `summary.calories` is the whole-day burn (calories out).
    let summary: WhoopSummary?
    /// Profile, used only to estimate resting (BMR) so Out can split into resting + active.
    var profile: Profile?
    /// Header label (e.g. day-scoped "ENERGY BALANCE · MON").
    var title: String = "ENERGY BALANCE"
    /// Optional deep-link into the owning tab (Calories).
    var onPress: (() -> Void)?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let kcalPerLb = 3500.0

    private var calsIn: Double { totals.calories }
    private var calsOut: Double? { summary?.calories }
    private var hasBurn: Bool { calsOut != nil }

    private var burnSplit: (total: Int, resting: Int, active: Int)? {
        guard let calsOut, let profile else { return nil }
        return Self.splitBurn(totalBurn: calsOut, bmr: EnergyMath.computeBmr(profile))
    }

    var body: some View {
        Card(metricAccent: Theme.Chart.calories) {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                CardHeader(title: title, icon: "arrow.up.arrow.down")

                HStack(alignment: .center, spacing: 0) {
                    stat(label: "In", value: Format.int(calsIn), unit: "cal",
                         underline: Theme.Colors.label, caption: "eaten")
                    divider
                    stat(label: "Out",
                         value: hasBurn ? Format.int(calsOut ?? 0) : "–",
                         unit: hasBurn ? "cal" : nil,
                         underline: Theme.Chart.calories,
                         caption: hasBurn ? "from Whoop" : "not linked")
                    divider
                    netStat
                }

                if hasBurn, let calsOut { netSlider(calsOut: calsOut) }

                if let burnSplit { burnBreakdown(burnSplit) }

                if hasBurn, let calsOut {
                    netSummary(calsOut: calsOut)
                } else {
                    connectHint
                }
            }
        }
    }

    private func netSlider(calsOut: Double) -> some View {
        let net = calsOut - calsIn
        let scale = 3000.0
        let frac = max(0, min(1, (net + scale) / (2 * scale)))
        let knob: CGFloat = 14
        return GeometryReader { geo in
            let usable = max(0, geo.size.width - knob)
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Theme.Chart.netEnergyGradient)
                    .frame(height: 8)
                    .padding(.horizontal, knob / 2)
                Circle()
                    .fill(Theme.Colors.surface)
                    .overlay(Circle().stroke(Theme.Colors.borderStrong, lineWidth: 1))
                    .frame(width: knob, height: knob)
                    .shadow(color: Color.black.opacity(0.10), radius: 3, x: 0, y: 1)
                    .offset(x: frac * usable)
            }
            .frame(height: knob)
        }
        .frame(height: knob)
        .accessibilityHidden(true)
    }

    private func stat(label: String, value: String, unit: String?, underline: Color, caption: String) -> some View {
        VStack(spacing: 2) {
            Txt(label, variant: .footnote, color: .labelSecondary)
            HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.xs) {
                Text(value)
                    .font(Theme.Font.statNumber)
                    .monospacedDigit()
                    .contentTransition(reduceMotion ? .identity : .numericText())
                    .foregroundStyle(Theme.Colors.label)
                if let unit { Txt(unit, variant: .footnote, color: .labelTertiary) }
            }
            Txt(caption, variant: .footnote, color: .labelTertiary)
            Capsule().fill(underline).frame(width: 20, height: 3).padding(.top, 2)
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var netStat: some View {
        if let calsOut {
            let net = calsOut - calsIn
            let color: Color = net > 0 ? Theme.Colors.success : (net < 0 ? Theme.Chart.calories : Theme.Colors.labelSecondary)
            let caption = net > 0 ? "deficit" : (net < 0 ? "surplus" : "even")
            stat(label: "Net", value: Format.int(abs(net)), unit: "cal", underline: color, caption: caption)
        } else {
            stat(label: "Net", value: "–", unit: nil, underline: Theme.Colors.labelTertiary, caption: "needs burn")
        }
    }

    private func burnBreakdown(_ split: (total: Int, resting: Int, active: Int)) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: "flame.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.Chart.calories)
                Txt("Total \(Format.int(Double(split.total))) = \(Format.int(Double(split.resting))) resting (BMR) + \(Format.int(Double(split.active))) active",
                    variant: .footnote, color: .labelSecondary)
            }
            Txt("Resting (BMR) is a Mifflin–St Jeor estimate from your profile. Active is everything above resting: all daily movement plus workouts, not just exercise.",
                variant: .footnote, color: .labelTertiary)
        }
        .padding(.top, Theme.Spacing.md)
        .overlay(alignment: .top) { Rectangle().fill(Theme.Colors.separator).frame(height: 1) }
    }

    private func netSummary(calsOut: Double) -> some View {
        let net = calsOut - calsIn
        let isDeficit = net > 0
        let isSurplus = net < 0
        let headlineColor: Color = isDeficit ? Theme.Colors.success : (isSurplus ? Theme.Chart.calories : Theme.Colors.labelSecondary)
        let headline = isDeficit
            ? "\(Format.int(net)) cal deficit"
            : (isSurplus ? "\(Format.int(abs(net))) cal surplus" : "In and out are even today")
        let lbPerWeek = isDeficit ? Format.oneDecimal((net * 7) / kcalPerLb) : nil

        return VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            HStack(spacing: Theme.Spacing.sm) {
                Circle().fill(headlineColor).frame(width: 8, height: 8)
                Txt(headline, variant: .bodyEmphasized)
            }
            if let lbPerWeek {
                Txt("At this rate ≈ \(lbPerWeek) lb/week · a rough estimate from your own numbers.",
                    variant: .footnote, color: .labelTertiary)
            } else {
                Txt("In and Out are your own logged numbers · this card just adds them up.",
                    variant: .footnote, color: .labelTertiary)
            }
        }
        .padding(.top, Theme.Spacing.md)
        .overlay(alignment: .top) { Rectangle().fill(Theme.Colors.separator).frame(height: 1) }
    }

    private var connectHint: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: "link")
                .font(.system(size: 13))
                .foregroundStyle(Theme.Colors.labelTertiary)
            Txt("Connect Whoop to see your burn and net for the day.",
                variant: .footnote, color: .labelTertiary)
        }
        .padding(.top, Theme.Spacing.md)
        .overlay(alignment: .top) { Rectangle().fill(Theme.Colors.separator).frame(height: 1) }
    }

    private var divider: some View {
        Rectangle()
            .fill(Theme.Colors.separator)
            .frame(width: 1)
            .padding(.vertical, Theme.Spacing.xs)
    }

    static func splitBurn(totalBurn: Double, bmr: Double) -> (total: Int, resting: Int, active: Int) {
        let total = Int(totalBurn.rounded())
        let resting = min(Int(bmr.rounded()), total)
        let active = max(0, total - resting)
        return (total, resting, active)
    }
}
