import SwiftUI

struct WeightTrendCard: View {
    @Environment(AppModel.self) private var appModel
    @State private var showLog = false

    /// The window the chart + delta cover.
    private let windowDays = 90

    private var series: [Double] { appModel.weightStore.historyLb(days: windowDays) }
    private var latest: Double? { appModel.weightStore.latestLb }
    private var change: Double? { appModel.weightStore.changeLb(days: windowDays) }

    var body: some View {
        Card(metricAccent: Theme.Chart.sleep) {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                HStack(spacing: Theme.Spacing.sm) {
                    CardHeader(title: "WEIGHT", icon: "scalemass.fill")
                    Spacer(minLength: 0)
                    Button { showLog = true } label: {
                        Label("Log", systemImage: "plus")
                            .font(Theme.Font.footnote.weight(.semibold))
                    }
                    .buttonStyle(.bordered)
                    .tint(Theme.Chart.sleep)
                }

                if let latest {
                    HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.sm) {
                        Text(Format.oneDecimal(latest))
                            .font(Theme.Font.statNumber)
                            .foregroundStyle(Theme.Colors.label)
                        Txt("lb", variant: .footnote, color: .labelTertiary)
                        if let change, abs(change) >= 0.05 {
                            changePill(change)
                        }
                        Spacer(minLength: 0)
                        Txt("last \(windowDays / 30) mo", variant: .footnote, color: .labelTertiary)
                    }

                    if series.count >= 2 {
                        GeometryReader { geo in
                            TrendChart(
                                points: series,
                                color: Theme.Chart.sleep,
                                height: 120,
                                width: geo.size.width
                            )
                        }
                        .frame(height: 120)
                    } else {
                        Txt("Log a few more weigh-ins to see your trend.",
                            variant: .footnote, color: .labelTertiary)
                    }
                } else {
                    emptyState
                }
            }
        }
        .sheet(isPresented: $showLog) {
            LogWeightSheet(initialLb: latest ?? appModel.profile.map { Units.kgToLb($0.weightKg) })
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Txt("No weigh-ins yet.", variant: .body, color: .labelSecondary)
            Button { showLog = true } label: {
                Label("Log your first weigh-in", systemImage: "plus")
                    .font(Theme.Font.footnote.weight(.semibold))
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.Chart.sleep)
        }
    }

    /// Small up/down pill: shows the change as an arrow + lb, never judged as good or bad.
    private func changePill(_ delta: Double) -> some View {
        let down = delta < 0
        return HStack(spacing: 2) {
            Image(systemName: down ? "arrow.down" : "arrow.up")
                .font(.system(size: 10, weight: .bold))
            Text("\(Format.oneDecimal(abs(delta))) lb")
                .font(Theme.Font.footnote.weight(.semibold))
        }
        .foregroundStyle(Theme.Colors.labelSecondary)
        .padding(.horizontal, Theme.Spacing.sm)
        .padding(.vertical, 3)
        .background(Capsule().fill(Theme.Colors.fieldBackground))
    }
}

struct LogWeightSheet: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss

    var initialLb: Double?

    @State private var lbText = ""
    @State private var bodyFatText = ""

    private var parsedLb: Double? {
        let v = Double(lbText.trimmingCharacters(in: .whitespaces))
        guard let v, v >= 20, v <= 1000 else { return nil }
        return v
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Weight") {
                    HStack {
                        TextField("0.0", text: $lbText)
                            .keyboardType(.decimalPad)
                        Text("lb").foregroundStyle(Theme.Colors.labelTertiary)
                    }
                }
                Section("Body fat (optional)") {
                    HStack {
                        TextField("–", text: $bodyFatText)
                            .keyboardType(.decimalPad)
                        Text("%").foregroundStyle(Theme.Colors.labelTertiary)
                    }
                }
            }
            .navigationTitle("Log weigh-in")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if let lb = parsedLb {
                            let bf = Double(bodyFatText.trimmingCharacters(in: .whitespaces))
                            appModel.logWeight(lb: lb, bodyFatPct: bf)
                            dismiss()
                        }
                    }
                    .disabled(parsedLb == nil)
                }
            }
            .onAppear {
                if lbText.isEmpty, let initialLb { lbText = Format.oneDecimal(initialLb) }
            }
        }
    }
}
