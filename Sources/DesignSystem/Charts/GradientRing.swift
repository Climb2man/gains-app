import SwiftUI

struct GradientRing: View {
    let progress: Double
    let title: String
    var caption: String? = nil
    var gradient: [Color] = [Theme.Chart.activity, Color(hex: "A8E000")]
    var track: Color = Theme.Colors.separator
    var lineWidth: CGFloat = 18
    var size: CGFloat = 168
    var animated: Bool = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false
    private var clamped: Double { min(max(progress, 0), 1) }
    private var drawn: Double { (animated && !reduceMotion) ? (shown ? clamped : 0) : clamped }

    var body: some View {
        ZStack {
            Circle()
                .stroke(track, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))

            Circle()
                .trim(from: 0, to: max(0.0001, drawn))
                .stroke(
                    AngularGradient(
                        gradient: Gradient(colors: gradient),
                        center: .center,
                        startAngle: .degrees(0),
                        endAngle: .degrees(360 * clamped)
                    ),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation((animated && !reduceMotion) ? .spring(response: 0.9, dampingFraction: 0.85) : nil, value: shown)
                .onAppear { shown = true }

            VStack(spacing: 2) {
                Text(title)
                    .font(Theme.Font.metricNumber)
                    .foregroundStyle(Theme.Colors.label)
                if let caption {
                    Text(caption)
                        .font(Theme.Font.subhead)
                        .foregroundStyle(Theme.Colors.labelSecondary)
                }
            }
        }
        .frame(width: size, height: size)
    }
}

#Preview {
    HStack(spacing: 24) {
        GradientRing(progress: 0.70, title: "70%", caption: "recovered")
        GradientRing(progress: 0.42, title: "42%", caption: "strain",
                     gradient: [Theme.Chart.calories, Color(hex: "FFCC00")])
    }
    .padding()
}
