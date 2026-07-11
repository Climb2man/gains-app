import SwiftUI

struct InteractiveLineChart: View {
    let values: [Double]
    var labels: [String]? = nil
    var rangeLow: Double? = nil
    var rangeHigh: Double? = nil
    var color: Color = Theme.Chart.strain
    var width: CGFloat = 320
    var height: CGFloat = 200
    var format: (Double) -> String = { String(Int($0.rounded())) }
    var accessibilityTitle: String = "Trend chart"

    @State private var selected: Int?

    private let vPadding: CGFloat = 16

    private var bounds: (lo: Double, hi: Double) {
        var all = values
        if let l = rangeLow { all.append(l) }
        if let h = rangeHigh { all.append(h) }
        guard let lo = all.min(), let hi = all.max() else { return (0, 1) }
        return lo == hi ? (lo - 1, hi + 1) : (lo, hi)
    }
    private func xOf(_ i: Int) -> CGFloat {
        values.count > 1 ? CGFloat(i) / CGFloat(values.count - 1) * width : width / 2
    }
    private func accessibilitySummary(for sel: Int?) -> String {
        guard let lo = values.min(), let hi = values.max() else { return "No data" }
        var parts: [String] = []
        if let s = sel, values.indices.contains(s) {
            if let labels, labels.indices.contains(s) {
                parts.append("\(labels[s]): \(format(values[s]))")
            } else {
                parts.append("Point \(s + 1) of \(values.count): \(format(values[s]))")
            }
        }
        parts.append("\(values.count) points, low \(format(lo)), high \(format(hi))")
        return parts.joined(separator: ", ")
    }

    var body: some View {
        let b = bounds
        let coords = values.indices.map { i in
            CGPoint(x: xOf(i),
                    y: LineGeometry.valueToY(values[i], min: b.lo, max: b.hi, height: height, vPadding: vPadding))
        }
        let sel = selected ?? (values.isEmpty ? nil : values.count - 1)
        let bandRect: CGRect? = {
            guard let lo = rangeLow, let hi = rangeHigh else { return nil }
            let yHi = LineGeometry.valueToY(max(lo, hi), min: b.lo, max: b.hi, height: height, vPadding: vPadding)
            let yLo = LineGeometry.valueToY(min(lo, hi), min: b.lo, max: b.hi, height: height, vPadding: vPadding)
            return CGRect(x: 0, y: yHi, width: width, height: yLo - yHi)
        }()

        ZStack(alignment: .topLeading) {
            StaticLineLayer(coords: coords, bandRect: bandRect, color: color,
                            width: width, height: height, vPadding: vPadding)
                .equatable()

            if let s = sel, coords.indices.contains(s) {
                SelectionLayer(point: coords[s], color: color, height: height)
                    .frame(width: width, height: height)
            }

            if let s = sel, coords.indices.contains(s) {
                let p = coords[s]
                let tipX = min(max(p.x - 32, 0), width - 64)
                VStack(spacing: 1) {
                    Text(format(values[s])).font(Theme.Font.footnote.weight(.bold))
                    if let labels, labels.indices.contains(s) {
                        Text(labels[s]).font(.system(size: 9)).opacity(0.8)
                    }
                }
                .foregroundStyle(Theme.Colors.onTint)
                .padding(.horizontal, Theme.Spacing.sm)
                .padding(.vertical, 4)
                .background(Capsule().fill(Theme.Colors.label))
                .offset(x: tipX, y: max(p.y - 40, 0))
            }
        }
        .frame(width: width, height: height, alignment: .topLeading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityTitle)
        .accessibilityValue(accessibilitySummary(for: sel))
        .accessibilityAdjustableAction { direction in
            guard let s = sel else { return }
            switch direction {
            case .increment: selected = min(s + 1, values.count - 1)
            case .decrement: selected = max(s - 1, 0)
            @unknown default: break
            }
        }
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { g in
                    guard values.count > 1 else { return }
                    let frac = max(0, min(1, g.location.x / width))
                    selected = Int((frac * CGFloat(values.count - 1)).rounded())
                }
        )
    }
}

private struct StaticLineLayer: View, Equatable {
    let coords: [CGPoint]
    let bandRect: CGRect?
    let color: Color
    let width: CGFloat
    let height: CGFloat
    let vPadding: CGFloat

    var body: some View {
        Canvas { ctx, _ in
            if let bandRect {
                ctx.fill(Path(roundedRect: bandRect, cornerRadius: 8), with: .color(color.opacity(0.07)))
            }
            guard !coords.isEmpty else { return }
            let line = ChartCurve.smoothLine(coords)
            if let f = coords.first, let l = coords.last {
                var area = line
                area.addLine(to: CGPoint(x: l.x, y: height))
                area.addLine(to: CGPoint(x: f.x, y: height))
                area.closeSubpath()
                ctx.fill(area, with: .linearGradient(
                    Gradient(colors: [color.opacity(0.14), color.opacity(0.0)]),
                    startPoint: CGPoint(x: 0, y: vPadding), endPoint: CGPoint(x: 0, y: height)))
            }
            ctx.stroke(line, with: .color(color),
                       style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
            for p in coords {
                let r: CGFloat = 3
                let d = Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2))
                ctx.fill(d, with: .color(Theme.Colors.surface))
                ctx.stroke(d, with: .color(color), style: StrokeStyle(lineWidth: 2))
            }
        }
        .frame(width: width, height: height)
    }
}

private struct SelectionLayer: View {
    let point: CGPoint
    let color: Color
    let height: CGFloat

    var body: some View {
        Canvas { ctx, _ in
            var rule = Path()
            rule.move(to: CGPoint(x: point.x, y: 0))
            rule.addLine(to: CGPoint(x: point.x, y: height))
            ctx.stroke(rule, with: .color(Theme.Colors.borderStrong),
                       style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
            let dot = Path(ellipseIn: CGRect(x: point.x - 6, y: point.y - 6, width: 12, height: 12))
            ctx.fill(dot, with: .color(color))
            ctx.stroke(dot, with: .color(Theme.Colors.surface), style: StrokeStyle(lineWidth: 3))
        }
        .allowsHitTesting(false)
    }
}

#Preview {
    InteractiveLineChart(
        values: [62, 58, 71, 65, 80, 74, 69, 77, 85, 79, 88],
        labels: ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun", "Mon", "Tue", "Wed", "Thu"],
        rangeLow: 60, rangeHigh: 85, color: Theme.Chart.strain, width: 340, height: 220
    ).padding()
}
