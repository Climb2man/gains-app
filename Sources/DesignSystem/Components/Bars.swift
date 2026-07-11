import SwiftUI

struct ProgressBar: View {
    let progress: Double
    var color: Color = Theme.Colors.tint
    var height: CGFloat = 8
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.Colors.fieldBackground)
                Capsule().fill(color)
                    .frame(width: geo.size.width * CGFloat(min(max(progress, 0), 1)))
            }
        }
        .frame(height: height)
    }
}

struct TotalsBar: View {
    let calories: Int
    let carbs: Int
    let protein: Int
    let fat: Int
    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            macro("flame.fill", "\(calories)", Theme.Chart.calories)
            dot
            macro("C", "\(carbs)", Theme.Chart.carbs, symbol: false)
            dot
            macro("P", "\(protein)", Theme.Chart.protein, symbol: false)
            dot
            macro("F", "\(fat)", Theme.Chart.fat, symbol: false)
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.vertical, Theme.Spacing.md)
        .background(Capsule().fill(Theme.Colors.surface))
        .compositingGroup()
        .shadow(color: Color.black.opacity(0.06), radius: 10, y: 3)
    }
    private var dot: some View { Circle().fill(Theme.Colors.separator).frame(width: 3, height: 3) }
    private func macro(_ label: String, _ value: String, _ color: Color, symbol: Bool = true) -> some View {
        HStack(spacing: 4) {
            if symbol { Image(systemName: label).font(.system(size: 13)).foregroundStyle(color) }
            else { Text(label).font(Theme.Font.footnote.weight(.bold)).foregroundStyle(color) }
            Text(value).font(Theme.Font.inlineNumber).foregroundStyle(Theme.Colors.label)
        }
    }
}

struct SheetHeader: View {
    let title: String
    var subtitle: String? = nil
    var onClose: () -> Void = {}
    var trailing: String? = nil
    var onTrailing: () -> Void = {}
    var body: some View {
        HStack {
            IconButton(systemName: "xmark", action: onClose)
            Spacer()
            VStack(spacing: 1) {
                Text(title).font(Theme.Font.bodyEmphasized)
                if let subtitle { Text(subtitle).font(Theme.Font.footnote).foregroundStyle(Theme.Colors.labelTertiary) }
            }
            Spacer()
            if let trailing { IconButton(systemName: trailing, action: onTrailing) }
            else { Color.clear.frame(width: 36, height: 36) }
        }
    }
}
