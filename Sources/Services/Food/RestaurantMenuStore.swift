import Foundation

struct RestaurantMenuStore: Sendable {
    let menus: [RestaurantMenu]

    init(bundle: Bundle = .main) {
        menus = Self.loadBundledMenus(from: bundle)
    }

    /// The brand menu matched by `line`, or nil. A menu matches when any of its aliases appears as a
    /// whole lowercase word in the line. First match wins (brands don't overlap).
    func match(line: String) -> RestaurantMenu? {
        let words = Set(
            line.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init)
        )
        return menus.first { menu in
            menu.aliases.contains { words.contains($0.lowercased()) }
        }
    }

    /// Decode every bundled JSON that parses as a `RestaurantMenu` (ignore any other JSON resource).
    private static func loadBundledMenus(from bundle: Bundle) -> [RestaurantMenu] {
        guard let urls = bundle.urls(forResourcesWithExtension: "json", subdirectory: nil) else {
            return []
        }
        let decoder = JSONDecoder()
        return urls.compactMap { url in
            guard let data = try? Data(contentsOf: url),
                  let menu = try? decoder.decode(RestaurantMenu.self, from: data),
                  !menu.items.isEmpty, !menu.aliases.isEmpty
            else { return nil }
            return menu
        }
    }
}
