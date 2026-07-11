import SwiftUI

struct MetricTileItem: Identifiable {
    let key: String
    let label: String
    var value: String?
    var unit: String?
    var accent: Color?
    var delta: (value: String, direction: DeltaDirection)?
    var caption: String?
    var icon: String?
    var iconColor: Color?
    var onTap: (() -> Void)?

    var id: String { key }
}

struct DeltaBadge: View {
    let value: String
    let direction: DeltaDirection

    private var tone: Color {
        switch direction {
        case .up: return Theme.Colors.success
        case .down: return Theme.Colors.danger
        case .flat: return Theme.Colors.labelSecondary
        }
    }

    private var symbol: String {
        switch direction {
        case .up: return "arrowtriangle.up.fill"
        case .down: return "arrowtriangle.down.fill"
        case .flat: return "minus"
        }
    }

    var body: some View {
        HStack(spacing: Theme.Spacing.xs) {
            Image(systemName: symbol)
                .font(.system(size: 10))
                .foregroundStyle(tone)
            Text(value)
                .font(Theme.Font.footnote.weight(.semibold))
                .foregroundStyle(tone)
        }
        .padding(.vertical, 2)
        .padding(.horizontal, Theme.Spacing.sm)
        .background(
            Capsule().fill(Theme.Colors.fieldBackground)
        )
    }
}

struct MetricTile: View {
    let item: MetricTileItem

    private var hasValue: Bool { item.value != nil }
    private var underline: Color { item.accent ?? Theme.Colors.separator }

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                HStack(spacing: Theme.Spacing.sm) {
                    Txt(item.label, variant: .footnote, color: .labelSecondary)
                    Spacer(minLength: 0)
                    if let delta = item.delta {
                        DeltaBadge(value: delta.value, direction: delta.direction)
                    } else if let icon = item.icon {
                        Image(systemName: icon)
                            .font(.system(size: 16))
                            .foregroundStyle(item.iconColor ?? Theme.Colors.labelTertiary)
                    }
                }

                HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.xs) {
                    if let value = item.value {
                        Text(value)
                            .font(Theme.Font.title1)
                            .foregroundStyle(item.accent ?? Theme.Colors.label)
                        if let unit = item.unit {
                            Txt(unit, variant: .subhead, color: .labelSecondary)
                        }
                    } else {
                        Txt("–", variant: .title1, color: .labelTertiary)
                    }
                }

                if let caption = item.caption {
                    Txt(caption, variant: .footnote, color: .labelTertiary)
                }

                Capsule()
                    .fill(underline)
                    .frame(height: 3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, Theme.Spacing.xs)
            }
        }
    }
}

struct MetricRow: View {
    let items: [MetricTileItem]
    var spacing: CGFloat = Theme.Spacing.md

    var body: some View {
        HStack(alignment: .top, spacing: spacing) {
            ForEach(items) { item in
                tile(for: item)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    @ViewBuilder
    private func tile(for item: MetricTileItem) -> some View {
        if let onTap = item.onTap {
            Button(action: onTap) {
                MetricTile(item: item)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(item.label), open detail")
        } else {
            MetricTile(item: item)
        }
    }
}
