import SwiftUI

struct QuickLogSheet: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            AddFoodView(appModel: appModel)
                .navigationTitle("Log food")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { dismiss() } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(Theme.Colors.labelSecondary)
                        }
                        .accessibilityLabel("Close")
                    }
                }
        }
    }
}

#if DEBUG
#Preview("Quick log") {
    QuickLogSheet()
        .environment(AppModel.sample)
}
#endif
