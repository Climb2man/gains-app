import SwiftUI

enum AppTab: String, CaseIterable, Hashable, Identifiable {
    case overview, calories, whoop, health

    var id: String { rawValue }

    /// The tab's base (unselected) SF Symbol.
    var systemImage: String {
        switch self {
        case .overview: "house"
        case .calories: "fork.knife"
        case .whoop: "waveform.path.ecg"
        case .health: "folder"
        }
    }

    /// The selected (filled) variant of the glyph. `fork.knife` and `waveform.path.ecg` have no `.fill`,
    /// so they reuse the base symbol; the tint + indicator carry the selected state for those.
    var selectedSystemImage: String {
        switch self {
        case .overview: "house.fill"
        case .calories: "fork.knife"
        case .whoop: "waveform.path.ecg"
        case .health: "folder.fill"
        }
    }

    var title: String {
        switch self {
        case .overview: "Overview"
        case .calories: "Calories"
        case .whoop: "Whoop"
        case .health: "Health"
        }
    }
}
