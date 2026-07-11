import SwiftUI

struct FoodEstimateReviewSheet: View {
    let review: FoodCaptureCoordinator.CaptureReview
    let bias: CalorieBias
    /// Confirm the (possibly edited) items → log them.
    let onConfirm: ([LoggedFoodItem]) -> Void
    let onCancel: () -> Void

    @State private var model: EstimateEditModel

    init(
        review: FoodCaptureCoordinator.CaptureReview,
        bias: CalorieBias,
        onConfirm: @escaping ([LoggedFoodItem]) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.review = review
        self.bias = bias
        self.onConfirm = onConfirm
        self.onCancel = onCancel
        _model = State(initialValue: EstimateEditModel(items: review.items))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    header
                    ForEach(model.drafts) { draft in
                        EstimateLineEditor(
                            draft: model.binding(for: draft),
                            onRemove: { model.remove(draft.id) }
                        )
                    }
                    Txt("These are estimates you can edit before logging. \(bias.disclosure)",
                        variant: .footnote, color: .labelTertiary, center: true)
                }
                .padding(Theme.Spacing.xl)
            }
            .background(Theme.Colors.background)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Log", action: confirm).disabled(!model.canConfirm)
                }
            }
            .safeAreaInset(edge: .bottom) { confirmBar }
        }
    }

    private var title: String {
        switch review.kind {
        case .photo: "Confirm photo"
        case .package: "Confirm label"
        case .menu: "Confirm"
        }
    }

    @ViewBuilder
    private var header: some View {
        Card {
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: headerIcon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.Colors.tint)
                Txt(headerTitle, variant: .bodyEmphasized)
            }
            if let description = review.description, !description.isEmpty {
                Txt(description, variant: .footnote, color: .labelSecondary)
            }
            Pill(text: "Estimate", icon: "sparkles", tone: .neutral)
        }
    }

    private var headerIcon: String {
        switch review.kind {
        case .photo: "camera"
        case .package: "shippingbox"
        case .menu: "doc.text.viewfinder"
        }
    }

    private var headerTitle: String {
        switch review.kind {
        case .photo: "What we saw"
        case .package: "From the label"
        case .menu: "Selected dishes"
        }
    }

    private var confirmBar: some View {
        VStack(spacing: 0) {
            HairlineDivider()
            HStack {
                Txt("\(Format.int(model.totalCalories)) kcal", variant: .bodyEmphasized)
                Spacer()
                Txt("\(model.drafts.count) item\(model.drafts.count == 1 ? "" : "s")",
                    variant: .footnote, color: .labelSecondary)
            }
            .padding(.horizontal, Theme.Spacing.xl)
            .padding(.vertical, Theme.Spacing.sm)
            PrimaryButton(title: "Log to today", disabled: !model.canConfirm, action: confirm)
                .padding(.horizontal, Theme.Spacing.xl)
                .padding(.bottom, Theme.Spacing.md)
        }
        .background(Theme.Colors.surface)
    }

    private func confirm() {
        guard model.canConfirm else { return }
        onConfirm(model.resolvedItems())
    }
}

private struct EstimateLineEditor: View {
    @Binding var draft: EstimateEditModel.Draft
    let onRemove: () -> Void

    var body: some View {
        Card {
            HStack {
                Txt(draft.name, variant: .bodyEmphasized).lineLimit(2)
                Spacer(minLength: Theme.Spacing.sm)
                Button(action: onRemove) {
                    Image(systemName: "minus.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(Theme.Colors.labelTertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove \(draft.name)")
            }
            HStack(spacing: Theme.Spacing.md) {
                EstimateNumberField(label: "Calories", value: $draft.calories)
                EstimateNumberField(label: "Protein g", value: $draft.proteinG)
            }
            HStack(spacing: Theme.Spacing.md) {
                EstimateNumberField(label: "Carbs g", value: $draft.carbsG)
                EstimateNumberField(label: "Fat g", value: $draft.fatG)
            }
        }
    }
}

private struct EstimateNumberField: View {
    let label: String
    @Binding var value: Double

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Txt(label, variant: .footnote, color: .labelSecondary)
            TextField(label, value: $value, format: .number)
                .font(Theme.Font.body)
                .foregroundStyle(Theme.Colors.label)
                .keyboardType(.decimalPad)
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.vertical, Theme.Spacing.md)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                        .fill(Theme.Colors.fieldBackground)
                )
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label), editable estimate")
    }
}

#if DEBUG
#Preview("Estimate review") {
    FoodEstimateReviewSheet(
        review: FoodCaptureCoordinator.CaptureReview(
            kind: .photo,
            items: [
                LoggedFoodItem(name: "Grilled chicken breast", calories: 280, proteinG: 52, carbsG: 0, fatG: 7,
                               confidenceScore: 70),
                LoggedFoodItem(name: "Brown rice", calories: 215, proteinG: 5, carbsG: 45, fatG: 2,
                               confidenceScore: 65),
            ],
            description: "Looks like a grilled chicken plate with brown rice and steamed broccoli.",
            photoLocalPath: "/local/photo.jpg"
        ),
        bias: .overestimateHigh,
        onConfirm: { _ in }, onCancel: {}
    )
}
#endif
