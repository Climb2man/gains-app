import SwiftUI

struct FoodLogRow: View {
    let entry: FoodJournalEntry
    var expanded: Bool
    let onTapDetails: () -> Void
    /// Optional "Is something wrong? Edit" affordance shown in the expanded state; users missed that
    /// lines were editable via swipe, so surface it on tap too.
    var onEdit: (() -> Void)? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            summaryButton
            if expanded { expandedDetail }
        }
        .padding(.vertical, Theme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(reduceMotion ? nil : .spring(response: 0.38, dampingFraction: 0.85), value: expanded)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint("Double tap for assumptions and to edit. This is an editable estimate.")
    }

    private var summaryButton: some View {
        Button(action: onTapDetails) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                headline
                if entry.status == .resolved {
                    subtitle
                    if hasChips { chipRow }
                } else if entry.status == .failed {
                    failedNote
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var expandedDetail: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            if let assumptions {
                Txt(assumptions, variant: .footnote, color: .labelSecondary)
            }
            if !citations.isEmpty {
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Txt("Sources", variant: .footnote, color: .labelTertiary)
                    ForEach(citations, id: \.self) { citation in
                        if let url = URL(string: citation) {
                            Link(destination: url) {
                                HStack(spacing: Theme.Spacing.xs) {
                                    Image(systemName: "link").font(.system(size: 11))
                                    Text(sourceHost(citation))
                                        .font(Theme.Font.footnote.weight(.medium))
                                        .lineLimit(1)
                                }
                                .foregroundStyle(Theme.Colors.tint)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            if let onEdit, entry.status == .resolved {
                Button(action: onEdit) {
                    HStack(spacing: Theme.Spacing.xs) {
                        Image(systemName: "pencil").font(.system(size: 12))
                        Text("Is something wrong? Edit").font(Theme.Font.footnote.weight(.medium))
                    }
                    .foregroundStyle(Theme.Colors.tint)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, 2)
        .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
    }

    private var headline: some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.md) {
            Txt(entry.displayTitle, variant: .body)
                .lineLimit(2)
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
                    Txt("estimating", variant: .footnote, color: .labelTertiary)
                }
            case .failed:
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.Colors.warning)
            case .resolved:
                if entry.isWaterOnly {
                    Image(systemName: "drop.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(Theme.Chart.recovery)
                } else {
                    Text("\(Format.int(entry.totalCalories))")
                        .font(Theme.Font.inlineNumber)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .foregroundStyle(Theme.Colors.label)
                }
            }
        }
        .transition(reduceMotion ? .identity : .opacity)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: entry.status)
    }

    private var subtitle: some View {
        Group {
            if entry.isWaterOnly {
                Txt(FoodLogFormat.water(entry.items.first?.waterMilliliters),
                    variant: .footnote, color: .labelSecondary)
            } else {
                Txt(FoodLogFormat.macroLine(protein: macroSum(\.proteinG),
                                            carbs: macroSum(\.carbsG),
                                            fat: macroSum(\.fatG)),
                    variant: .footnote, color: .labelSecondary)
            }
        }
    }

    private var chipRow: some View {
        HStack(spacing: Theme.Spacing.md) {
            MetaTag(icon: provenanceIcon, text: provenanceText,
                    accessibility: provenanceAccessibility)
            if let level = confidenceShort {
                MetaTag(icon: "circle.fill", text: level, color: confidenceStatus.color,
                        iconSize: 9, accessibility: "\(level) confidence")
            }
            if let count = sourcesCount {
                MetaTag(icon: "link", text: "\(count)", color: Theme.Colors.tint,
                        accessibility: "\(count) source\(count == 1 ? "" : "s")")
            }
            Spacer(minLength: 0)
        }
    }

    private var failedNote: some View {
        Txt("Couldn't estimate. Tap to edit or retry.", variant: .footnote, color: .warning)
    }

    /// True when there are provenance/confidence chips to show (resolved, non-water, has an item).
    private var hasChips: Bool { firstItem != nil }

    private var firstItem: LoggedFoodItem? {
        entry.isWaterOnly ? nil : entry.items.first
    }

    private var confidenceStatus: StatusTone {
        FoodLogFormat.confidenceStatus(firstItem?.confidenceScore)
    }

    /// The confidence level word only ("High" / "Medium" / "Low"); the slim tag drops the trailing
    /// " confidence" so three tags fit one line.
    private var confidenceShort: String? {
        FoodLogFormat.confidenceLabel(firstItem?.confidenceScore)?
            .replacingOccurrences(of: " confidence", with: "")
    }

    /// Number of cited sources when the pipeline cited references for a novel food; nil otherwise.
    private var sourcesCount: Int? {
        guard let item = firstItem, !item.citations.isEmpty else { return nil }
        return item.citations.count
    }

    /// The provenance tag's glyph and short label: the user's typed numbers, a cache hit, or an
    /// AI/database estimate (the safety default).
    private var provenanceIcon: String {
        switch firstItem?.provenance {
        case .stated: "person.text.rectangle"
        case .cached: "clock.arrow.circlepath"
        default: "sparkles"
        }
    }

    private var provenanceText: String {
        switch firstItem?.provenance {
        case .stated: "Your numbers"
        case .cached: "Saved"
        default: "Estimate"
        }
    }

    private var provenanceAccessibility: String {
        switch firstItem?.provenance {
        case .stated: "From your own numbers"
        case .cached: "From a saved entry"
        default: "Estimated"
        }
    }

    private var assumptions: String? {
        let notes = entry.items.compactMap(\.assumptions).filter { !$0.isEmpty }
        return notes.isEmpty ? nil : notes.joined(separator: " ")
    }

    /// All cited source URLs across the line's items, de-duplicated in order; shown as tappable links in
    /// the expanded drawer.
    private var citations: [String] {
        var seen = Set<String>()
        var out: [String] = []
        for url in entry.items.flatMap(\.citations) where !url.isEmpty && seen.insert(url).inserted {
            out.append(url)
        }
        return out
    }

    /// A clean display label for a source: its host without the "www." prefix, falling back to the URL.
    private func sourceHost(_ urlString: String) -> String {
        guard let host = URL(string: urlString)?.host else { return urlString }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    private func macroSum(_ keyPath: KeyPath<LoggedFoodItem, Double>) -> Double {
        entry.items.reduce(0) { $0 + $1[keyPath: keyPath] }
    }

    private var accessibilityLabel: String {
        switch entry.status {
        case .pending: "\(entry.displayTitle), estimating macros"
        case .failed: "\(entry.displayTitle), estimate failed"
        case .resolved:
            entry.isWaterOnly
                ? "\(entry.displayTitle), \(FoodLogFormat.water(entry.items.first?.waterMilliliters))"
                : "\(entry.displayTitle), \(Format.int(entry.totalCalories)) kilocalories, estimate"
        }
    }
}

/// One lightweight tag in the row's metadata line: a small glyph and short label tinted by `color`. No
/// capsule fill or heavy padding (the old chips were too fat to fit), and `fixedSize` so the short
/// label never truncates. `accessibility` supplies the full spoken text so VoiceOver doesn't read just
/// "High" / "2".
private struct MetaTag: View {
    let icon: String
    let text: String
    var color: Color = Theme.Colors.labelSecondary
    var iconSize: CGFloat = 10
    var accessibility: String

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: icon).font(.system(size: iconSize, weight: .semibold))
            Text(text).font(.system(size: 11, weight: .medium))
        }
        .foregroundStyle(color)
        .lineLimit(1)
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibility)
    }
}

#if DEBUG
#Preview("Rows") {
    let resolved = FoodJournalEntry(
        foodText: "chicken burrito bowl with guac",
        items: [LoggedFoodItem(name: "Chicken burrito bowl", calories: 720, proteinG: 42,
                               carbsG: 78, fatG: 26, assumptions: "Assumed a regular bowl with brown rice, black beans, and a side of guac. Estimates lean high to protect your deficit.",
                               confidenceScore: 62)],
        status: .resolved, loggedAt: FoodLogStore.isoNow())
    let pending = FoodJournalEntry(foodText: "two scrambled eggs and toast",
                                   status: .pending, loggedAt: FoodLogStore.isoNow())
    let water = FoodJournalEntry(foodText: "16 oz water",
                                 items: [LoggedFoodItem(name: "16 oz water", calories: 0,
                                                        isWaterEntry: true, waterMilliliters: 473)],
                                 status: .resolved, loggedAt: FoodLogStore.isoNow())
    return VStack(spacing: 0) {
        FoodLogRow(entry: resolved, expanded: true, onTapDetails: {})
        HairlineDivider()
        FoodLogRow(entry: pending, expanded: false, onTapDetails: {})
        HairlineDivider()
        FoodLogRow(entry: water, expanded: false, onTapDetails: {})
    }
    .padding()
    .background(Theme.Colors.surface)
}
#endif
