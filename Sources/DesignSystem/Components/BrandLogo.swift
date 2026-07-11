import SwiftUI

struct BrandLogo: View {
    enum Brand {
        case appleHealth
        case whoop
        case openRouter

        /// Bundled-asset name; drop a PNG here to override the rendered mark.
        var assetName: String {
            switch self {
            case .appleHealth: return "brand-applehealth"
            case .whoop: return "brand-whoop"
            case .openRouter: return "brand-openrouter"
            }
        }

        /// Offline fallback tile color (also the asset-less brand color).
        var fallbackColor: Color {
            switch self {
            case .appleHealth: return .white
            case .whoop: return Color(hex: "0A0A0A")
            case .openRouter: return Color(hex: "4F46E5")
            }
        }

        /// Bold monogram drawn on the offline fallback tile.
        var monogram: String {
            switch self {
            case .appleHealth: return ""
            case .whoop: return "W"
            case .openRouter: return "OR"
            }
        }

        var accessibilityName: String {
            switch self {
            case .appleHealth: return "Apple Health"
            case .whoop: return "Whoop"
            case .openRouter: return "OpenRouter"
            }
        }
    }

    let brand: Brand
    let size: CGFloat

    init(_ brand: Brand, size: CGFloat = 28) {
        self.brand = brand
        self.size = size
    }

    private var corner: CGFloat {
        min(Theme.Radius.sm, size * 0.28)
    }

    var body: some View {
        content
            .frame(width: size, height: size)
            .accessibilityElement()
            .accessibilityLabel(brand.accessibilityName)
    }

    @ViewBuilder
    private var content: some View {
        if let bundled = bundledImage {
            bundled
                .resizable()
                .scaledToFill()
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
        } else if brand == .appleHealth {
            appleHealthMark
        } else {
            fallbackTile
        }
    }

    /// Returns an `Image` only if the asset exists. `UIImage(named:)` probes safely,
    /// returning nil for a missing asset rather than a broken `Image`.
    private var bundledImage: Image? {
        #if canImport(UIKit)
        if UIImage(named: brand.assetName) != nil {
            return Image(brand.assetName)
        }
        #endif
        return nil
    }

    private var appleHealthMark: some View {
        RoundedRectangle(cornerRadius: corner, style: .continuous)
            .fill(.white)
            .overlay(
                Image(systemName: "heart.fill")
                    .font(.system(size: size * 0.5, weight: .bold))
                    .foregroundStyle(Color(hex: "FA3C4C"))
            )
            .overlay(
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .stroke(Theme.Colors.separator, lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.12), radius: 2, x: 0, y: 1)
    }

    /// Branded monogram tile shown only when a brand has no bundled asset.
    private var fallbackTile: some View {
        RoundedRectangle(cornerRadius: corner, style: .continuous)
            .fill(brand.fallbackColor)
            .overlay(
                Text(brand.monogram)
                    .font(.system(size: size * (brand.monogram.count > 1 ? 0.36 : 0.5), weight: .heavy))
                    .foregroundStyle(.white)
                    .minimumScaleFactor(0.5)
                    .padding(2)
            )
    }
}

#if DEBUG
#Preview("BrandLogo") {
    VStack(spacing: Theme.Spacing.xl) {
        HStack(spacing: Theme.Spacing.lg) {
            BrandLogo(.appleHealth)
            BrandLogo(.whoop)
            BrandLogo(.openRouter)
        }
        HStack(spacing: Theme.Spacing.lg) {
            BrandLogo(.appleHealth, size: 44)
            BrandLogo(.whoop, size: 44)
            BrandLogo(.openRouter, size: 44)
        }
    }
    .padding(Theme.Spacing.xl)
    .background(Theme.Colors.background)
}
#endif
