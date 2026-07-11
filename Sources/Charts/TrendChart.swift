import SwiftUI

struct TrendChart: View {
    let points: [Double]
    var color: Color = Theme.Chart.protein
    var height: CGFloat = 120
    var width: CGFloat = 300
    var showLastDot: Bool = true
    var fill: Bool = true
    var labels: [String]? = nil
    var labelCount: Int = 4
    var gridLines: Int = 0
    var goalValue: Double? = nil

    private let vPadding: CGFloat = 8
    private let labelBand: CGFloat = 18

    var body: some View {
        let hasData = !points.isEmpty
        let hasLabels = (labels?.isEmpty == false)
        let labelArray = labels ?? []
        let plotH = hasLabels ? height - labelBand : height

        VStack(spacing: 0) {
            Canvas { context, _ in
                guard hasData else {
                    var base = Path()
                    base.move(to: CGPoint(x: 0, y: plotH / 2))
                    base.addLine(to: CGPoint(x: width, y: plotH / 2))
                    context.stroke(
                        base,
                        with: .color(Theme.Colors.separator),
                        style: StrokeStyle(lineWidth: 2, dash: [4, 6])
                    )
                    return
                }

                let coords = LineGeometry.lineCoords(
                    points, width: width, height: plotH, vPadding: vPadding, extra: goalValue
                )

                if gridLines > 0 {
                    for i in 0...gridLines {
                        let y = vPadding + (plotH - vPadding) * CGFloat(i) / CGFloat(gridLines)
                        var line = Path()
                        line.move(to: CGPoint(x: 0, y: y))
                        line.addLine(to: CGPoint(x: width, y: y))
                        context.stroke(
                            line,
                            with: .color(Theme.Colors.separator.opacity(0.6)),
                            style: StrokeStyle(lineWidth: 1)
                        )
                    }
                }

                let linePath = ChartCurve.smoothLine(coords)

                if fill, let first = coords.first, let last = coords.last {
                    let baseY = plotH - vPadding / 2
                    var area = linePath
                    area.addLine(to: CGPoint(x: last.x, y: baseY))
                    area.addLine(to: CGPoint(x: first.x, y: baseY))
                    area.closeSubpath()
                    context.fill(
                        area,
                        with: .linearGradient(
                            Gradient(colors: [color.opacity(0.18), color.opacity(0.0)]),
                            startPoint: CGPoint(x: 0, y: 0),
                            endPoint: CGPoint(x: 0, y: plotH)
                        )
                    )
                }

                if let goalValue {
                    let bounds = LineGeometry.valueBounds(points, extra: goalValue)
                    let goalY = LineGeometry.valueToY(
                        goalValue, min: bounds.min, max: bounds.max, height: plotH, vPadding: vPadding
                    )
                    var goalLine = Path()
                    goalLine.move(to: CGPoint(x: 0, y: goalY))
                    goalLine.addLine(to: CGPoint(x: width, y: goalY))
                    context.stroke(
                        goalLine,
                        with: .color(Theme.Colors.labelSecondary),
                        style: StrokeStyle(lineWidth: 1.5, dash: [5, 5])
                    )
                }

                context.stroke(
                    linePath,
                    with: .linearGradient(
                        Gradient(colors: Theme.Chart.gradientStops(for: color)),
                        startPoint: CGPoint(x: 0, y: 0),
                        endPoint: CGPoint(x: width, y: 0)
                    ),
                    style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round)
                )

                if showLastDot, let last = coords.last {
                    let halo = Path(ellipseIn: CGRect(x: last.x - 5, y: last.y - 5, width: 10, height: 10))
                    context.fill(halo, with: .color(Theme.Colors.surface))
                    let dot = Path(ellipseIn: CGRect(x: last.x - 3.5, y: last.y - 3.5, width: 7, height: 7))
                    context.fill(dot, with: .color(color))
                }
            }
            .frame(width: width, height: plotH)

            if hasData, hasLabels {
                let idxs = ChartAxis.sparseLabelIndices(labelArray, count: labelCount)
                let coords = LineGeometry.lineCoords(
                    points, width: width, height: plotH, vPadding: vPadding, extra: goalValue
                )
                ChartAxisLabels(
                    indices: idxs,
                    lastIndex: labelArray.count - 1,
                    width: width,
                    band: labelBand,
                    text: { labelArray[$0] },
                    x: { coords[safe: $0]?.x ?? 0 }
                )
            }
        }
        .frame(width: width)
    }
}

extension TrendChart {
    static func dual(
        primary: [Double],
        reference: [Double],
        primaryColor: Color = Theme.Chart.sleep,
        referenceColor: Color = Theme.Colors.labelTertiary,
        format: @escaping (Double) -> String = { $0.formatted(.number.precision(.fractionLength(1))) },
        height: CGFloat = 140,
        width: CGFloat = 300,
        labels: [String]? = nil,
        labelCount: Int = 4
    ) -> some View {
        DualTrendChart(
            primary: primary,
            reference: reference,
            primaryColor: primaryColor,
            referenceColor: referenceColor,
            format: format,
            height: height,
            width: width,
            labels: labels,
            labelCount: labelCount
        )
    }
}

private struct DualTrendChart: View {
    let primary: [Double]
    let reference: [Double]
    let primaryColor: Color
    let referenceColor: Color
    let format: (Double) -> String
    let height: CGFloat
    let width: CGFloat
    let labels: [String]?
    let labelCount: Int

    private let vPadding: CGFloat = 10
    private let labelBand: CGFloat = 18

    var body: some View {
        let hasData = !primary.isEmpty || !reference.isEmpty
        let hasLabels = (labels?.isEmpty == false)
        let labelArray = labels ?? []
        let plotH = hasLabels ? height - labelBand : height
        let all = primary + reference
        let bounds = LineGeometry.valueBounds(all)

        VStack(spacing: 0) {
            Canvas { context, _ in
                guard hasData else {
                    var base = Path()
                    base.move(to: CGPoint(x: 0, y: plotH / 2))
                    base.addLine(to: CGPoint(x: width, y: plotH / 2))
                    context.stroke(
                        base,
                        with: .color(Theme.Colors.separator),
                        style: StrokeStyle(lineWidth: 2, dash: [4, 6])
                    )
                    return
                }

                if !reference.isEmpty {
                    let refCoords = coords(reference, bounds: bounds, plotH: plotH)
                    context.stroke(
                        ChartCurve.smoothLine(refCoords),
                        with: .color(referenceColor),
                        style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round, dash: [5, 4])
                    )
                    drawEndLabel(context, coords: refCoords, series: reference, color: referenceColor, plotH: plotH)
                }

                if !primary.isEmpty {
                    let priCoords = coords(primary, bounds: bounds, plotH: plotH)
                    context.stroke(
                        ChartCurve.smoothLine(priCoords),
                        with: .linearGradient(
                            Gradient(colors: Theme.Chart.gradientStops(for: primaryColor)),
                            startPoint: CGPoint(x: 0, y: 0),
                            endPoint: CGPoint(x: width, y: 0)
                        ),
                        style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round)
                    )
                    if let last = priCoords.last {
                        let halo = Path(ellipseIn: CGRect(x: last.x - 5, y: last.y - 5, width: 10, height: 10))
                        context.fill(halo, with: .color(Theme.Colors.surface))
                        let dot = Path(ellipseIn: CGRect(x: last.x - 3.5, y: last.y - 3.5, width: 7, height: 7))
                        context.fill(dot, with: .color(primaryColor))
                    }
                    drawEndLabel(context, coords: priCoords, series: primary, color: primaryColor, plotH: plotH)
                }
            }
            .frame(width: width, height: plotH)

            if hasData, hasLabels {
                let idxs = ChartAxis.sparseLabelIndices(labelArray, count: labelCount)
                let xs = coords(primary.isEmpty ? reference : primary, bounds: bounds, plotH: plotH)
                ChartAxisLabels(
                    indices: idxs,
                    lastIndex: labelArray.count - 1,
                    width: width,
                    band: labelBand,
                    text: { labelArray[$0] },
                    x: { xs[safe: $0]?.x ?? 0 }
                )
            }
        }
        .frame(width: width)
    }

    private func coords(_ values: [Double], bounds: (min: Double, max: Double), plotH: CGFloat) -> [CGPoint] {
        let n = values.count
        let stepX = n > 1 ? width / CGFloat(n - 1) : 0
        return values.enumerated().map { i, v in
            CGPoint(
                x: n > 1 ? CGFloat(i) * stepX : width / 2,
                y: LineGeometry.valueToY(v, min: bounds.min, max: bounds.max, height: plotH, vPadding: vPadding)
            )
        }
    }

    private func drawEndLabel(
        _ context: GraphicsContext, coords: [CGPoint], series: [Double], color: Color, plotH: CGFloat
    ) {
        guard let last = coords.last, let value = series.last else { return }
        let text = Text(format(value))
            .font(Theme.Font.footnote.weight(.semibold))
            .foregroundStyle(color)
        let resolved = context.resolve(text)
        let size = resolved.measure(in: CGSize(width: width, height: plotH))
        let x = min(width - size.width / 2 - 2, max(size.width / 2, last.x))
        let y = max(size.height / 2, last.y - 12)
        context.draw(resolved, at: CGPoint(x: x, y: y))
    }
}
