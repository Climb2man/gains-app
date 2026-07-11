import SwiftUI

struct SegmentedPills: View {
    let options: [String]
    @Binding var selection: Int

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Theme.Spacing.sm) {
                ForEach(options.indices, id: \.self) { i in
                    Button { selection = i } label: {
                        Text(options[i])
                            .font(Theme.Font.subhead.weight(.medium))
                            .foregroundStyle(i == selection ? Theme.Colors.onTint : Theme.Colors.labelSecondary)
                            .padding(.horizontal, Theme.Spacing.md)
                            .padding(.vertical, Theme.Spacing.sm)
                            .background(
                                Capsule().fill(i == selection ? Theme.Colors.label : Theme.Colors.fieldBackground)
                            )
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(i == selection ? .isSelected : [])
                }
            }
        }
    }
}
