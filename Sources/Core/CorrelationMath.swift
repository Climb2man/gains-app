import Foundation

enum CorrelationMath {
    /// Pearson correlation r between paired samples `x` and `y`.
    ///
    /// Returns `nil` when the series differ in length, fewer than 2 pairs remain, or either
    /// column has zero variance (r is undefined, not 0). `n` is the pair count.
    static func pearson(_ x: [Double], _ y: [Double]) -> (r: Double, n: Int)? {
        guard x.count == y.count, x.count >= 2 else { return nil }
        let n = Double(x.count)
        let meanX = x.reduce(0, +) / n
        let meanY = y.reduce(0, +) / n

        var covSum = 0.0
        var varXSum = 0.0
        var varYSum = 0.0
        for i in x.indices {
            let dx = x[i] - meanX
            let dy = y[i] - meanY
            covSum += dx * dy
            varXSum += dx * dx
            varYSum += dy * dy
        }

        let denom = (varXSum * varYSum).squareRoot()
        guard denom > 0 else { return nil }
        let r = covSum / denom
        return (max(-1, min(1, r)), x.count)
    }

    /// Correlate each day's `x` with the next day's `y` (x[i] with y[i+1]), e.g. today's strain
    /// vs. tomorrow's recovery. Inputs must be aligned by day, oldest to newest.
    static func laggedPearson(x: [Double], y: [Double]) -> (r: Double, n: Int)? {
        guard x.count == y.count, x.count >= 2 else { return nil }
        let lagX = Array(x.dropLast())
        let lagY = Array(y.dropFirst())
        return pearson(lagX, lagY)
    }

    /// Approximate two-sided significance flag for a Pearson r at sample size n, from the
    /// t-statistic t = r · √((n-2) / (1-r²)) on n-2 degrees of freedom.
    ///
    /// Tests |t| against a lookup of two-sided 0.05 critical values rather than computing an exact
    /// p-value. Reported only as a binary "significant at ~0.05" flag, always shown alongside n.
    ///
    /// Returns `false` for n < 3 (no usable degrees of freedom); a perfect |r| ≥ 1 with n ≥ 3
    /// counts as significant.
    static func isSignificant(r: Double, n: Int) -> Bool {
        guard n >= 3, abs(r) < 1 else { return n >= 3 && abs(r) >= 1 }
        let df = n - 2
        let t = abs(r) * (Double(df) / (1 - r * r)).squareRoot()
        return t >= criticalT(df: df)
    }

    /// Two-sided 0.05 critical t-values by degrees of freedom (Student's t table), falling back to
    /// the asymptotic z (1.96) for large df.
    private static func criticalT(df: Int) -> Double {
        switch df {
        case 1: return 12.706
        case 2: return 4.303
        case 3: return 3.182
        case 4: return 2.776
        case 5: return 2.571
        case 6: return 2.447
        case 7: return 2.365
        case 8: return 2.306
        case 9: return 2.262
        case 10: return 2.228
        case 11: return 2.201
        case 12: return 2.179
        case 13: return 2.160
        case 14: return 2.145
        case 15: return 2.131
        case 16: return 2.120
        case 17: return 2.110
        case 18: return 2.101
        case 19: return 2.093
        case 20: return 2.086
        case 21...25: return 2.060
        case 26...30: return 2.042
        case 31...40: return 2.021
        case 41...60: return 2.000
        default: return 1.96
        }
    }

    /// Describes r as a phrase like "a strong positive pattern", using the common |r| bands
    /// (weak < 0.3 ≤ moderate < 0.5 ≤ strong). Describes how two columns move together. Never a
    /// cause, a recommendation, or a judgment about the person.
    static func describe(r: Double) -> String {
        let strength: String
        switch abs(r) {
        case ..<0.1: return "almost no pattern"
        case ..<0.3: strength = "a weak"
        case ..<0.5: strength = "a moderate"
        default: strength = "a strong"
        }
        let direction = r >= 0 ? "positive" : "negative"
        return "\(strength) \(direction) pattern"
    }
}
