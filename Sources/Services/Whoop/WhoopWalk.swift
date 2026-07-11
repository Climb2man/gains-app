import Foundation

enum WhoopWalk {
    /// A tile pulled from the tree: its `type` discriminator + `content` bag.
    struct Tile: Sendable, Equatable {
        let type: String
        let content: JSONValue
    }

    /// Walk the whole payload and collect every node that has a string `type` and an
    /// object `content`. The recovery/strain projections scan this flat list for their
    /// SCORE_GAUGE / CONTRIBUTORS_TILE / ACTIVITY tiles by id.
    static func collectTiles(_ node: JSONValue) -> [Tile] {
        var out: [Tile] = []
        func visit(_ n: JSONValue) {
            switch n {
            case let .array(items):
                for item in items { visit(item) }
            case let .object(o):
                if let type = o["type"]?.stringValue, let content = o["content"], content.isObject {
                    out.append(Tile(type: type, content: content))
                }
                for v in o.values { visit(v) }
            default:
                break
            }
        }
        visit(node)
        return out
    }

    /// Depth-first: the first object node matching `predicate`, or nil.
    /// The predicate receives the node so callers can inspect its keys.
    static func findFirst(_ node: JSONValue, where predicate: (JSONValue) -> Bool) -> JSONValue? {
        switch node {
        case .object(let o):
            if predicate(node) { return node }
            for v in o.values {
                if let found = findFirst(v, where: predicate) { return found }
            }
        case .array(let a):
            for v in a {
                if let found = findFirst(v, where: predicate) { return found }
            }
        default:
            break
        }
        return nil
    }

    /// The first node whose `type` equals `type`, or nil.
    static func findByType(_ node: JSONValue, _ type: String) -> JSONValue? {
        findFirst(node) { $0["type"].stringValue == type }
    }

    /// Find a DETAILS_GRAPHING_CARD whose content.card_title contains `titleSubstr`
    /// (case-insensitive). The sleep deep-dive identifies its stat cards by title.
    static func findDetailsCardByTitle(_ node: JSONValue, _ titleSubstr: String) -> JSONValue? {
        let upper = titleSubstr.uppercased()
        return findFirst(node) { n in
            guard n["type"].stringValue == "DETAILS_GRAPHING_CARD" else { return false }
            let title = n["content"]["card_title"].stringValue ?? ""
            return title.uppercased().contains(upper)
        }
    }

    /// Strip a trailing % and commas from a label and parse a number; nil for time
    /// labels ("7:24" is a time, not a number).
    static func labelToNumber(_ label: String?) -> Double? {
        guard let label else { return nil }
        if isClockLabel(label) { return nil }
        let cleaned = label
            .replacing(",", with: "")
            .replacing(/%$/, with: "")
        guard let n = Double(cleaned), n.isFinite else { return nil }
        return n
    }

    /// "H:MM" / "HH:MM" → milliseconds; nil if not a clock-duration label.
    static func timeLabelToMs(_ label: String?) -> Double? {
        guard let label, let (hours, minutes) = clockParts(label) else { return nil }
        return Double((hours * 3600 + minutes * 60)) * 1000
    }

    /// True when `label` is exactly `\d+:\d+` (a clock/time label like "7:24").
    private static func isClockLabel(_ label: String) -> Bool {
        clockParts(label) != nil
    }

    /// Parse a `\d+:\d+` label into (hours, minutes); nil if it isn't that exact shape.
    private static func clockParts(_ label: String) -> (Int, Int)? {
        let parts = label.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2,
              let h = Int(parts[0]), let m = Int(parts[1]),
              !parts[0].isEmpty, !parts[1].isEmpty
        else { return nil }
        return (h, m)
    }
}
