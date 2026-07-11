import SwiftUI

struct BarcodeFoundCard: View {
    let item: LoggedFoodItem
    let onLog: () -> Void
    let onScanAgain: () -> Void

    var body: some View {
        VStack(spacing: Theme.Spacing.lg) {
            Card {
                HStack(spacing: Theme.Spacing.sm) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Theme.Colors.success)
                    Txt("Product found", variant: .bodyEmphasized)
                }

                Txt(item.name, variant: .title2)

                HStack(spacing: Theme.Spacing.sm) {
                    Txt("\(Format.int(item.calories)) kcal", variant: .body, color: .label)
                    Txt("·", variant: .body, color: .labelTertiary)
                    Txt(FoodLogFormat.macroLine(protein: item.proteinG, carbs: item.carbsG, fat: item.fatG),
                        variant: .body, color: .labelSecondary)
                }

                if let assumptions = item.assumptions, !assumptions.isEmpty {
                    Txt(assumptions, variant: .footnote, color: .labelTertiary)
                }

                Txt("Macro numbers are estimates. "
                    + "You can edit this line after logging.",
                    variant: .footnote, color: .labelTertiary)
            }

            VStack(spacing: Theme.Spacing.sm) {
                Button(action: onLog) {
                    Txt("Log this food", variant: .bodyEmphasized, color: .onTint, center: true)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Theme.Spacing.md)
                        .background(
                            RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous)
                                .fill(Theme.Colors.tint)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Log \(item.name)")

                Button(action: onScanAgain) {
                    Txt("Scan a different item", variant: .body, color: .tint, center: true)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Theme.Spacing.sm)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(Theme.Spacing.lg)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

#if DEBUG
#Preview("Found") {
    BarcodeFoundCard(
        item: LoggedFoodItem(
            name: "Clif Builders Protein Bar (Chocolate)",
            calories: 280, proteinG: 20, carbsG: 30, fatG: 9,
            assumptions: "Matched from Open Food Facts (scaled to one serving)."
        ),
        onLog: {}, onScanAgain: {}
    )
    .background(Theme.Colors.background)
}
#endif
