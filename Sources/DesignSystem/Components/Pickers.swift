import SwiftUI

struct NumberStepper: View {
    @Binding var value: Int
    var range: ClosedRange<Int> = 0...999
    var step: Int = 1
    var unit: String? = nil

    @State private var editing = false
    @State private var draft = ""
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            RepeatButton(icon: "minus") { adjust(-step) }
            valueView
            RepeatButton(icon: "plus") { adjust(step) }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(unit ?? "Value")
        .accessibilityValue("\(value)")
        .accessibilityHint("Double-tap to type a value")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: adjust(step)
            case .decrement: adjust(-step)
            @unknown default: break
            }
        }
    }

    @ViewBuilder private var valueView: some View {
        if editing {
            HStack(spacing: 3) {
                TextField("", text: $draft)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.center)
                    .font(Theme.Font.statNumber)
                    .foregroundStyle(Theme.Colors.label)
                    .monospacedDigit()
                    .focused($focused)
                    .fixedSize()
                    .onChange(of: focused) { _, isFocused in
                        if !isFocused { commit() }
                    }
                unitLabel
            }
            .frame(minWidth: 72)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { focused = false }
                }
            }
        } else {
            Button { beginEditing() } label: {
                HStack(spacing: 3) {
                    Text("\(value)").font(Theme.Font.statNumber).foregroundStyle(Theme.Colors.label)
                        .monospacedDigit()
                    unitLabel
                }
                .frame(minWidth: 72)
                .fixedSize(horizontal: true, vertical: false)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHidden(true)
        }
    }

    @ViewBuilder private var unitLabel: some View {
        if let unit { Text(unit).font(Theme.Font.callout).foregroundStyle(Theme.Colors.labelSecondary) }
    }

    private func adjust(_ delta: Int) {
        if editing { focused = false }
        value = min(range.upperBound, max(range.lowerBound, value + delta))
    }

    private func beginEditing() {
        draft = "\(value)"
        editing = true
        DispatchQueue.main.async { focused = true }
    }

    private func commit() {
        if let typed = Int(draft) {
            value = min(range.upperBound, max(range.lowerBound, typed))
        }
        editing = false
    }
}

/// +/− button that fires once on tap, then auto-repeats with acceleration while held. Used by `NumberStepper`.
private struct RepeatButton: View {
    let icon: String
    let action: () -> Void

    @State private var pressing = false
    @State private var timer: Timer?
    @State private var interval: Double = 0.3

    var body: some View {
        Image(systemName: icon).font(.system(size: 14, weight: .bold))
            .foregroundStyle(Theme.Colors.label).frame(width: 36, height: 36)
            .background(Circle().fill(Theme.Colors.fieldBackground))
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
            .opacity(pressing ? 0.5 : 1)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in if !pressing { begin() } }
                    .onEnded { _ in end() }
            )
    }

    private func begin() {
        pressing = true
        action()
        interval = 0.3
        scheduleNext()
    }

    private func scheduleNext() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { _ in
            action()
            interval = max(0.04, interval * 0.82)
            scheduleNext()
        }
    }

    private func end() {
        timer?.invalidate()
        timer = nil
        pressing = false
    }
}

struct RadioPicker: View {
    let options: [String]
    @Binding var selection: Int
    var body: some View {
        VStack(spacing: 0) {
            ForEach(options.indices, id: \.self) { i in
                Button { selection = i } label: {
                    HStack {
                        Text(options[i]).font(Theme.Font.body).foregroundStyle(Theme.Colors.label)
                        Spacer()
                        Image(systemName: i == selection ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 20))
                            .foregroundStyle(i == selection ? Theme.Colors.tint : Theme.Colors.borderStrong)
                    }
                    .padding(.vertical, Theme.Spacing.md)
                }.buttonStyle(.plain)
                if i < options.count - 1 { Divider() }
            }
        }
    }
}

struct WeekDateStrip: View {
    let days: [String]
    @Binding var selected: Int
    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            ForEach(days.indices, id: \.self) { i in
                Button { selected = i } label: {
                    Text(days[i])
                        .font(Theme.Font.subhead.weight(.semibold))
                        .foregroundStyle(i == selected ? Theme.Colors.onTint : Theme.Colors.labelSecondary)
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(i == selected ? Theme.Colors.tint : Theme.Colors.fieldBackground))
                }.buttonStyle(.plain)
            }
        }
    }
}
