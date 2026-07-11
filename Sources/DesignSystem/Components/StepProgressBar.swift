import SwiftUI

struct StepProgressBar: View {
    /// The 1-based current step (e.g. 1...total). Clamped into range.
    let current: Int
    /// Total steps in the flow.
    let total: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var clampedCurrent: Int { min(max(current, 0), total) }

    var body: some View {
        HStack(spacing: Theme.Spacing.xs) {
            ForEach(0 ..< max(total, 0), id: \.self) { i in
                Capsule()
                    .fill(i < clampedCurrent ? Theme.Colors.tint : Theme.Colors.fieldBackground)
                    .frame(height: 6)
                    .frame(maxWidth: .infinity)
            }
        }
        .animation(reduceMotion ? nil : Theme.Motion.stepTransition, value: clampedCurrent)
        .accessibilityElement()
        .accessibilityLabel("Step \(clampedCurrent) of \(total)")
    }
}

#if DEBUG
#Preview("StepProgressBar") {
    VStack(spacing: Theme.Spacing.xl) {
        StepProgressBar(current: 1, total: 4)
        StepProgressBar(current: 2, total: 4)
        StepProgressBar(current: 3, total: 4)
        StepProgressBar(current: 4, total: 4)
    }
    .padding(Theme.Spacing.xl)
    .background(Theme.Colors.background)
}
#endif
