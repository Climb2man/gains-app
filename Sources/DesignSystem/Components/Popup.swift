import SwiftUI

private struct PopupModifier<PopupContent: View>: ViewModifier {
    @Binding var isPresented: Bool
    @ViewBuilder var popup: () -> PopupContent

    func body(content: Content) -> some View {
        content.overlay {
            if isPresented {
                ZStack {
                    Color.black.opacity(0.35)
                        .ignoresSafeArea()
                        .transition(.opacity)
                        .onTapGesture { isPresented = false }
                    popup()
                        .transition(.scale(scale: 0.88).combined(with: .opacity))
                }
                .animation(.spring(response: 0.35, dampingFraction: 0.82), value: isPresented)
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.82), value: isPresented)
    }
}

extension View {
    func popup<C: View>(isPresented: Binding<Bool>, @ViewBuilder content: @escaping () -> C) -> some View {
        modifier(PopupModifier(isPresented: isPresented, popup: content))
    }
}
