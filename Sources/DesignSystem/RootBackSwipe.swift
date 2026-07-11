import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

extension View {
    /// Disables the edge back-swipe only at the NavigationStack root, so a horizontal carousel there
    /// keeps its own pan. Pushed detail screens still swipe back.
    @ViewBuilder
    func suppressRootBackSwipe() -> some View {
        #if canImport(UIKit)
        background(RootBackSwipeController())
        #else
        self
        #endif
    }
}

#if canImport(UIKit)
private struct RootBackSwipeController: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> Proxy { Proxy() }
    func updateUIViewController(_ proxy: Proxy, context: Context) { proxy.install() }

    /// Invisible child VC that SwiftUI hosts inside the NavigationStack. Its `navigationController`
    /// resolves to the stack's UINavigationController, whose pop recognizer we re-delegate.
    final class Proxy: UIViewController {
        private let popDelegate = RootOnlyPopDelegate()

        override func didMove(toParent parent: UIViewController?) {
            super.didMove(toParent: parent)
            install()
        }

        func install() {
            DispatchQueue.main.async { [weak self] in
                guard let self,
                      let nav = self.navigationController,
                      let pop = nav.interactivePopGestureRecognizer else { return }
                self.popDelegate.navigationController = nav
                pop.delegate = self.popDelegate
                pop.isEnabled = true
            }
        }
    }

    /// Allows the swipe-back only when there's a pushed screen to pop; refuses at the root.
    final class RootOnlyPopDelegate: NSObject, UIGestureRecognizerDelegate {
        weak var navigationController: UINavigationController?
        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            (navigationController?.viewControllers.count ?? 0) > 1
        }
    }
}
#endif
