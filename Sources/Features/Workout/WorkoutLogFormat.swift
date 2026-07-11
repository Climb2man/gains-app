import Foundation

enum WorkoutLogFormat {
    /// One set as a compact string, e.g. "10 × 135 lb", "8 (bodyweight)", "12 × 60 lb @8". Reps × load,
    /// then RPE when present. Warm-up / drop-set tags are shown as chips by the row, not folded in here.
    static func set(_ set: WorkoutSet) -> String {
        var parts: [String] = []
        if let reps = set.reps {
            parts.append("\(reps)")
        }
        if let weight = set.weight {
            let unit = set.weightUnit ?? "lb"
            let load: String
            if ["kg", "kgs", "kilogram", "kilograms"].contains(unit.lowercased()) {
                load = "\(Format.oneDecimal(Units.kgToLb(weight))) lb"
            } else {
                load = "\(Format.oneDecimal(weight)) \(unit)"
            }
            parts.append(parts.isEmpty ? load : "× \(load)")
        } else if set.reps != nil {
            parts.append("(bodyweight)")
        }
        var line = parts.joined(separator: " ")
        if let rpe = set.rpe {
            line += " @\(Format.oneDecimal(rpe))"
        }
        if line.trimmingCharacters(in: .whitespaces).isEmpty {
            line = set.raw
        }
        return line
    }

    /// A one-line summary of an exercise's sets for the collapsed row, e.g. "3 sets · 10 × 135 lb".
    /// Working sets only in the count (warm-ups noted separately by the row).
    static func exerciseSummary(_ exercise: WorkoutExercise) -> String {
        let count = exercise.workingSetCount
        let setsWord = count == 1 ? "set" : "sets"
        if let first = exercise.sets.first(where: { !$0.isWarmup }) {
            return "\(count) \(setsWord) · \(set(first))"
        }
        return "\(count) \(setsWord)"
    }

    /// A session subtitle, e.g. "4 exercises · 12 sets". Descriptive count only.
    static func sessionSummary(_ entry: WorkoutEntry) -> String {
        let exWord = entry.exerciseCount == 1 ? "exercise" : "exercises"
        let setWord = entry.totalSetCount == 1 ? "set" : "sets"
        return "\(entry.exerciseCount) \(exWord) · \(entry.totalSetCount) \(setWord)"
    }

    /// The same count summary for a saved shortcut chip subtitle.
    static func shortcutSummary(_ shortcut: WorkoutShortcut) -> String {
        let word = shortcut.exerciseCount == 1 ? "exercise" : "exercises"
        return "\(shortcut.exerciseCount) \(word)"
    }
}
