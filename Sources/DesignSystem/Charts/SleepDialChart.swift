import SwiftUI

struct SleepDialChart: View {
    var progress: Double = 0.72
    var size: CGFloat = 160
    var tint: [Color] = [Theme.Chart.strain, Theme.Chart.recovery]

    var body: some View {
        ZStack {
            Circle().stroke(Color.white.opacity(0.14), lineWidth: 10)
            Circle()
                .trim(from: 0, to: min(max(progress, 0), 1))
                .stroke(AngularGradient(gradient: Gradient(colors: tint), center: .center),
                        style: StrokeStyle(lineWidth: 10, lineCap: .round))
                .rotationEffect(.degrees(-90))

            Circle()
                .stroke(Color.white.opacity(0.18), style: StrokeStyle(lineWidth: 1, dash: [1, 4]))
                .padding(26)

            Image(systemName: "sparkles")
                .font(.system(size: 18))
                .foregroundStyle(Theme.Chart.recovery)

            Image(systemName: "bed.double.fill")
                .font(.system(size: 12)).foregroundStyle(.white)
                .offset(y: -size / 2 + 5)
            Image(systemName: "sun.max.fill")
                .font(.system(size: 12)).foregroundStyle(Color(hex: "FFCC00"))
                .offset(x: -size / 4, y: size / 3)
            Image(systemName: "alarm.fill")
                .font(.system(size: 12)).foregroundStyle(.white.opacity(0.8))
                .offset(x: size / 3, y: size / 4)
        }
        .frame(width: size, height: size)
    }
}
