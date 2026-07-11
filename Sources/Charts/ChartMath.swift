import CoreGraphics
import SwiftUI

enum ChartAxis {
    private static func nearestNonBlank(_ labels: [String], _ idx: Int) -> Int {
        if !labels[idx].isEmpty { return idx }
        let n = labels.count
        var d = 1
        while d < n {
            if idx - d >= 0, !labels[idx - d].isEmpty { return idx - d }
            if idx + d < n, !labels[idx + d].isEmpty { return idx + d }
            d += 1
        }
        return idx
    }

    static func sparseLabelIndices(_ labels: [String], count: Int) -> [Int] {
        let n = labels.count
        if n == 0 { return [] }
        if n == 1 { return labels[0].isEmpty ? [] : [0] }
        let want = max(2, min(count, n))
        var picked = Set<Int>()
        for i in 0..<want {
            let target = Int((Double(i) * Double(n - 1) / Double(want - 1)).rounded())
            let idx = nearestNonBlank(labels, target)
            if !labels[idx].isEmpty { picked.insert(idx) }
        }
        return picked.sorted()
    }

    static func sparseIndices(_ n: Int, count: Int) -> [Int] {
        if n <= 0 { return [] }
        if n == 1 { return [0] }
        let want = max(2, min(count, n))
        var set = Set<Int>()
        for i in 0..<want {
            set.insert(Int((Double(i) * Double(n - 1) / Double(want - 1)).rounded()))
        }
        return set.sorted()
    }
}

enum ChartCurve {
    static let tension: CGFloat = 6

    static func smoothLine(_ pts: [CGPoint]) -> Path {
        var path = Path()
        guard let first = pts.first else { return path }
        path.move(to: first)
        if pts.count == 1 { return path }
        for i in 0..<(pts.count - 1) {
            let p0 = pts[i == 0 ? 0 : i - 1]
            let p1 = pts[i]
            let p2 = pts[i + 1]
            let p3 = pts[i + 2 < pts.count ? i + 2 : pts.count - 1]
            let c1 = CGPoint(
                x: p1.x + (p2.x - p0.x) / tension,
                y: p1.y + (p2.y - p0.y) / tension
            )
            let c2 = CGPoint(
                x: p2.x - (p3.x - p1.x) / tension,
                y: p2.y - (p3.y - p1.y) / tension
            )
            path.addCurve(to: p2, control1: c1, control2: c2)
        }
        return path
    }
}

enum AxisAnchor {
    case start, middle, end

    static func forTick(idx: Int, lastIndex: Int) -> AxisAnchor {
        if idx == 0 { return .start }
        if idx == lastIndex { return .end }
        return .middle
    }

    var alignment: Alignment {
        switch self {
        case .start: return .leading
        case .middle: return .center
        case .end: return .trailing
        }
    }
}
