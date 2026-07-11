import SwiftUI
import UIKit

enum GainsTabBarAppearance {
    /// Configure the global `UITabBar` appearance: a clear/system chrome background, a blue selected
    /// item (glyph + label), and a tertiary-slate unselected item. No custom selection indicator image,
    /// so the system draws its light selection, never the heavy grey capsule.
    static func apply() {
        let appearance = UITabBarAppearance()
        appearance.configureWithDefaultBackground()

        let tint = UIColor(Theme.Colors.tint)
        let unselected = UIColor(Theme.Colors.labelTertiary)

        for item in [
            appearance.stackedLayoutAppearance,
            appearance.inlineLayoutAppearance,
            appearance.compactInlineLayoutAppearance,
        ] {
            item.selected.iconColor = tint
            item.selected.titleTextAttributes = [.foregroundColor: tint]
            item.normal.iconColor = unselected
            item.normal.titleTextAttributes = [.foregroundColor: unselected]
        }

        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
    }
}
