import SwiftUI

struct CategoryBadge: View {
    let text: String
    var color: Color = Theme.Colors.tint

    var body: some View {
        Text(text)
            .font(Theme.Font.footnote.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, Theme.Spacing.sm)
            .padding(.vertical, 4)
            .background(Capsule().fill(color.opacity(0.15)))
    }
}

struct BiomarkerBadge: View {
    let count: Int
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "testtube.2").font(.system(size: 11, weight: .semibold))
            Text("\(count) biomarkers").font(Theme.Font.footnote.weight(.semibold))
        }
        .foregroundStyle(Theme.Chart.activity)
        .padding(.horizontal, Theme.Spacing.sm)
        .padding(.vertical, 4)
        .background(Capsule().fill(Theme.Chart.activity.opacity(0.12)))
    }
}

struct HealthRecordRow: View {
    let category: String
    var categoryColor: Color = Theme.Colors.tint
    let title: String
    let date: String
    var biomarkers: Int? = nil

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            RoundedRectangle(cornerRadius: Theme.Radius.sm)
                .fill(Theme.Colors.fieldBackground)
                .frame(width: 52, height: 68)
                .overlay(
                    Image(systemName: "doc.text")
                        .font(.system(size: 20))
                        .foregroundStyle(Theme.Colors.labelTertiary)
                )

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    CategoryBadge(text: category, color: categoryColor)
                    if let biomarkers { BiomarkerBadge(count: biomarkers) }
                }
                Text(title)
                    .font(Theme.Font.bodyEmphasized)
                    .foregroundStyle(Theme.Colors.label)
                    .lineLimit(1)
                Text("Date of service: \(date)")
                    .font(Theme.Font.footnote)
                    .foregroundStyle(Theme.Colors.labelTertiary)
            }

            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.Colors.labelTertiary)
        }
        .padding(.vertical, Theme.Spacing.sm)
    }
}
