import SwiftUI

struct WorkoutLogRow: View {
    let entry: WorkoutEntry
    var expanded: Bool
    let onTapDetails: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: onTapDetails) {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                headline
                if entry.status == .resolved {
                    if hasChips { chipRow }
                    if expanded { exerciseDetail }
                } else if entry.status == .failed {
                    failedNote
                }
            }
            .padding(.vertical, Theme.Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(.rect)
            .animation(reduceMotion ? nil : .spring(response: 0.38, dampingFraction: 0.85), value: expanded)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint("Double tap to expand the exercises. This is your logged training, editable.")
    }

    private var headline: some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.md) {
            VStack(alignment: .leading, spacing: 2) {
                Txt(entry.displayTitle, variant: .bodyEmphasized)
                    .lineLimit(2)
                if entry.status == .resolved {
                    Txt(WorkoutLogFormat.sessionSummary(entry), variant: .footnote, color: .labelSecondary)
                }
            }
            Spacer(minLength: Theme.Spacing.sm)
            trailingValue
        }
    }

    @ViewBuilder
    private var trailingValue: some View {
        Group {
            switch entry.status {
            case .pending:
                HStack(spacing: Theme.Spacing.xs) {
                    ProgressView().controlSize(.small).tint(Theme.Colors.tint)
                    Txt("reading", variant: .footnote, color: .labelTertiary)
                }
            case .failed:
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.Colors.warning)
            case .resolved:
                Image(systemName: expanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.Colors.labelTertiary)
            }
        }
        .transition(reduceMotion ? .identity : .opacity)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: entry.status)
    }

    private var chipRow: some View {
        HStack(spacing: Theme.Spacing.xs) {
            if entry.lowConfidence {
                StatusBadge(text: "Check this", status: .warning, icon: "exclamationmark.circle.fill")
            }
            Spacer(minLength: 0)
        }
    }

    private var exerciseDetail: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HairlineDivider()
            ForEach(entry.exercises) { exercise in
                ExerciseBlock(exercise: exercise)
            }
        }
        .padding(.top, Theme.Spacing.xs)
        .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
    }

    private var failedNote: some View {
        Txt("Couldn't read that workout. Tap to edit or retry.", variant: .footnote, color: .warning)
    }

    private var hasChips: Bool { entry.lowConfidence }

    private var accessibilityLabel: String {
        switch entry.status {
        case .pending: "\(entry.displayTitle), reading your workout"
        case .failed: "\(entry.displayTitle), couldn't read the workout"
        case .resolved: "\(entry.displayTitle), \(WorkoutLogFormat.sessionSummary(entry))"
        }
    }
}

/// One exercise within the expanded session: the name (with a superset group tag and optional note),
/// then its sets as rows.
private struct ExerciseBlock: View {
    let exercise: WorkoutExercise

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            HStack(spacing: Theme.Spacing.sm) {
                if let group = exercise.group {
                    Txt(group, variant: .footnote, color: .tint)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Theme.Colors.tintSoft))
                }
                Txt(exercise.name, variant: .subhead)
                    .lineLimit(2)
            }
            if let note = exercise.note {
                Txt(note, variant: .footnote, color: .labelTertiary)
            }
            ForEach(Array(exercise.sets.enumerated()), id: \.element.id) { index, set in
                SetRow(index: index + 1, set: set)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// One set row within an exercise: an index, the formatted reps × load, and warm-up / drop-set chips.
private struct SetRow: View {
    let index: Int
    let set: WorkoutSet

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Txt("\(index)", variant: .footnote, color: .labelTertiary)
                .frame(width: 18, alignment: .leading)
                .monospacedDigit()
            Txt(WorkoutLogFormat.set(set), variant: .footnote, color: .labelSecondary)
            if set.isWarmup {
                Chip(text: "Warm-up", icon: "flame")
            }
            if set.isDropSet {
                Chip(text: "Drop set", icon: "arrow.down.right")
            }
            Spacer(minLength: 0)
        }
    }
}

#if DEBUG
#Preview("Workout rows") {
    let push = WorkoutEntry(
        date: WorkoutStore.isoNow(),
        title: "Push day",
        exercises: [
            WorkoutExercise(name: "Barbell Bench Press", note: "felt strong", sets: [
                WorkoutSet(reps: 12, weight: 95, weightUnit: "lb", isWarmup: true, raw: "warmup 12@95"),
                WorkoutSet(reps: 10, weight: 135, weightUnit: "lb", raw: "10@135"),
                WorkoutSet(reps: 8, weight: 135, weightUnit: "lb", rpe: 8, raw: "8@135 @8"),
            ]),
            WorkoutExercise(name: "Incline Dumbbell Press", group: "A", sets: [
                WorkoutSet(reps: 10, weight: 50, weightUnit: "lb", raw: "10@50"),
                WorkoutSet(reps: 8, weight: 50, weightUnit: "lb", isDropSet: true, raw: "8@50 drop"),
            ]),
        ],
        rawText: "bench 3x10 @135, incline DB 10,10,8 @50",
        status: .resolved
    )
    let pending = WorkoutEntry(date: WorkoutStore.isoNow(),
                               rawText: "squats 5x5 @225", status: .pending)
    return VStack(spacing: 0) {
        WorkoutLogRow(entry: push, expanded: true, onTapDetails: {})
        HairlineDivider()
        WorkoutLogRow(entry: pending, expanded: false, onTapDetails: {})
    }
    .padding()
    .background(Theme.Colors.surface)
}
#endif
