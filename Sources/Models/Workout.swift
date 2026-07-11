import Foundation

/// One set of an exercise. Every field is optional except `raw`, because notations vary wildly
/// (`10@60`, `bodyweight x12`, `30s plank`): the parser fills what it can read and leaves the rest
/// nil rather than fabricating a number.
struct WorkoutSet: Codable, Equatable, Identifiable, Sendable {
    var id: String
    /// Repetitions for this set, when the user stated them. Nil for time/distance-only work.
    var reps: Int?
    /// The load as the user typed it (e.g. `60`). Paired with `weightUnit`; nil for bodyweight.
    var weight: Double?
    /// The unit the user wrote, preserved verbatim ("lb", "kg", "lbs"). Defaults to the imperial "lb"
    /// only when a weight is present but the user named no unit. Nil for bodyweight / unit-less work.
    var weightUnit: String?
    /// Rate of Perceived Exertion (0…10), when the user logged one (`@8 RPE`). Nil otherwise.
    var rpe: Double?
    /// A warm-up set (e.g. the user wrote "warmup" / "wu"). Drives a lighter chip; excluded from any
    /// future "working set" math. Defaults false.
    var isWarmup: Bool
    /// A drop-set continuation of the prior set (the user wrote "drop" / "dropset"). A tag only. The
    /// set still stands on its own row. Defaults false. (TODO: progression history may group these.)
    var isDropSet: Bool
    /// The user's original fragment for this set (e.g. "8,8,7@60" yields three sets, each carrying
    /// its slice) so the source notation is never lost.
    var raw: String

    init(
        id: String = UUID().uuidString,
        reps: Int? = nil,
        weight: Double? = nil,
        weightUnit: String? = nil,
        rpe: Double? = nil,
        isWarmup: Bool = false,
        isDropSet: Bool = false,
        raw: String = ""
    ) {
        self.id = id
        self.reps = reps
        self.weight = weight
        self.weightUnit = weightUnit
        self.rpe = rpe
        self.isWarmup = isWarmup
        self.isDropSet = isDropSet
        self.raw = raw
    }
}

/// One exercise in a logged session: a normalized name, an optional note, an optional superset
/// `group` tag, and its sets. The UI groups the session by exercise (and by superset group).
struct WorkoutExercise: Codable, Equatable, Identifiable, Sendable {
    var id: String
    /// The normalized exercise name (e.g. "Incline Dumbbell Press"), title-cased by the parser.
    var name: String
    /// A short note the user attached (a cue, a machine name, a tempo). Shown under the name. Nil when
    /// none. Free-form; never advice.
    var note: String?
    /// A superset/circuit tag (e.g. "A" / "Superset 1") when the user paired exercises. Exercises that
    /// share a non-nil `group` are shown bracketed together. Nil for a standalone exercise.
    var group: String?
    /// The sets performed, in order.
    var sets: [WorkoutSet]

    init(
        id: String = UUID().uuidString,
        name: String,
        note: String? = nil,
        group: String? = nil,
        sets: [WorkoutSet] = []
    ) {
        self.id = id
        self.name = name
        self.note = note
        self.group = group
        self.sets = sets
    }

    /// Total working sets (warm-ups excluded): the headline count shown on the exercise row.
    var workingSetCount: Int { sets.filter { !$0.isWarmup }.count }
}

/// Resolution state for the optimistic UI: `.pending` on insert, `.resolved` once the parse fills
/// in exercises, `.failed` if the parse couldn't read it (the user can then edit the raw text).
enum WorkoutEntryStatus: String, Codable, Equatable, Sendable {
    case pending
    case resolved
    case failed
}

/// Where a session came from: typed + parsed, or a re-logged shortcut.
enum WorkoutSource: String, Codable, Equatable, Sendable {
    /// Typed into the composer and parsed by the AI.
    case typed
    /// Re-logged in one tap from a saved/recent shortcut (zero AI).
    case shortcut
}

/// One logged workout session: the user's raw typed text plus the exercises the AI parsed out. A
/// real `date` timestamp is stored, `status` drives the optimistic row, and `lowConfidence` flags a
/// shaky parse the user should check.
struct WorkoutEntry: Codable, Equatable, Identifiable, Sendable {
    var id: String
    /// ISO 8601 timestamp (with fractional seconds) of when the session was logged.
    var date: String
    /// An optional session title (e.g. "Push day"). The parser may infer one from the text; nil when
    /// there isn't a clear title.
    var title: String?
    /// The parsed exercises. Empty while `.pending`.
    var exercises: [WorkoutExercise]
    /// The user's original natural-language text for this session (what they typed / re-typed).
    var rawText: String
    /// Resolution state for the optimistic UI.
    var status: WorkoutEntryStatus
    /// Where this session came from (typed + parsed, or a re-logged shortcut).
    var source: WorkoutSource
    /// True when the AI flagged the parse as uncertain (ambiguous notation). The UI shows a "check
    /// this" chip so the user verifies. Defaults false; never blocks logging.
    var lowConfidence: Bool

    init(
        id: String = UUID().uuidString,
        date: String,
        title: String? = nil,
        exercises: [WorkoutExercise] = [],
        rawText: String,
        status: WorkoutEntryStatus = .pending,
        source: WorkoutSource = .typed,
        lowConfidence: Bool = false
    ) {
        self.id = id
        self.date = date
        self.title = title
        self.exercises = exercises
        self.rawText = rawText
        self.status = status
        self.source = source
        self.lowConfidence = lowConfidence
    }

    /// Total exercises in the session: the headline count on the row.
    var exerciseCount: Int { exercises.count }

    /// Total sets across all exercises (warm-ups included): a secondary glance metric.
    var totalSetCount: Int { exercises.reduce(0) { $0 + $1.sets.count } }

    /// The display title for the row: the parsed title, falling back to the user's raw text, then a
    /// generic label so a row always reads something.
    var displayTitle: String {
        if let title, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return title }
        let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        return "Workout"
    }
}

/// A nicknamed, re-loggable workout (e.g. "Push day A"). Stores the full parsed snapshot so
/// recalling it inserts instantly with no AI calls, offline. `useCount` orders the quick-add
/// suggestions (most-used first).
struct WorkoutShortcut: Codable, Equatable, Identifiable, Sendable {
    var id: String
    /// The user's nickname, e.g. "Push day". Re-logs the snapshot in one tap.
    var nickname: String
    /// The full parsed snapshot to re-insert.
    var exercises: [WorkoutExercise]
    /// How many times it's been re-logged. Sorts the quick-add row.
    var useCount: Int
    /// ISO 8601 timestamps.
    var createdAt: String
    var updatedAt: String

    init(
        id: String = UUID().uuidString,
        nickname: String,
        exercises: [WorkoutExercise],
        useCount: Int = 0,
        createdAt: String,
        updatedAt: String
    ) {
        self.id = id
        self.nickname = nickname
        self.exercises = exercises
        self.useCount = useCount
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    /// Total exercises in the snapshot: the chip subtitle.
    var exerciseCount: Int { exercises.count }
}

/// What the UX hands the parser to resolve a new session. A struct (not a bare string) so the
/// request can grow metadata (a preferred unit, an edit base) without breaking callers.
struct WorkoutParseRequest: Sendable {
    var text: String

    init(text: String) {
        self.text = text
    }
}

/// The parser's result for one session: the normalized exercises, an optional inferred title, and
/// the low-confidence flag. A struct (not a bare array) so it can carry per-parse metadata.
struct WorkoutParseResult: Sendable {
    var title: String?
    var exercises: [WorkoutExercise]
    var lowConfidence: Bool

    init(title: String? = nil, exercises: [WorkoutExercise], lowConfidence: Bool = false) {
        self.title = title
        self.exercises = exercises
        self.lowConfidence = lowConfidence
    }
}
