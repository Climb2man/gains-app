import SwiftUI

enum StatusTone { case good, warning, bad, neutral
    var color: Color {
        switch self {
        case .good: return Theme.Chart.activity
        case .warning: return Theme.Colors.warning
        case .bad: return Theme.Colors.danger
        case .neutral: return Theme.Colors.labelSecondary
        }
    }
}

struct StatusBadge: View {
    let text: String
    var status: StatusTone = .neutral
    var icon: String? = nil
    var body: some View {
        HStack(spacing: 4) {
            if let icon { Image(systemName: icon).font(.system(size: 10, weight: .bold)) }
            Text(text).font(Theme.Font.footnote.weight(.semibold))
        }
        .foregroundStyle(status.color)
        .padding(.horizontal, Theme.Spacing.sm)
        .padding(.vertical, 4)
        .background(Capsule().fill(status.color.opacity(0.14)))
    }
}

struct TrendBadge: View {
    let up: Bool
    var delta: String? = nil
    var goodWhenUp: Bool = true
    private var color: Color { (up == goodWhenUp) ? Theme.Chart.activity : Theme.Colors.warning }
    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: up ? "arrow.up" : "arrow.down").font(.system(size: 10, weight: .bold))
            if let delta { Text(delta).font(Theme.Font.footnote.weight(.semibold)) }
        }
        .foregroundStyle(color)
        .padding(.horizontal, 6).padding(.vertical, 3)
        .background(Capsule().fill(color.opacity(0.15)))
    }
}

struct CountBadge: View {
    let count: Int
    var tint: Color = Theme.Colors.tint
    var body: some View {
        Text("\(count)")
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(Theme.Colors.onTint)
            .frame(minWidth: 18, minHeight: 18)
            .padding(.horizontal, 4)
            .background(Capsule().fill(tint))
    }
}
