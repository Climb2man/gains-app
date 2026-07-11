import Foundation

/// A confident Open Food Facts match, normalized into the shared item shape.
/// `servingDescription` carries the DB's serving text so the portion step can rescale.
struct OpenFoodFactsMatch: Equatable, Sendable {
    /// Nutrition for one serving (or per-100g when the product has no serving), as a
    /// `LoggedFoodItem` so it flows through the same router path as an AI result.
    var item: LoggedFoodItem
    /// Serving description from the DB (e.g. "1 bottle (500 ml)"), if any, for the portion step.
    var servingDescription: String?
    /// The barcode this resolved from, for a barcode lookup (provenance).
    var barcode: String?
}

/// The Open Food Facts seam (external dependency behind a protocol). A confident match returns a
/// normalized `OpenFoodFactsMatch`; `nil` means no confident match, so the router falls through to
/// the Sonar path. Throws only on a transport failure the caller treats as a miss.
protocol OpenFoodFactsClient: Sendable {
    /// Free-text search for a generic/branded food. Returns the best confident match, or `nil`.
    func searchProduct(query: String) async throws -> OpenFoodFactsMatch?
    /// Barcode (UPC/EAN) lookup. Only the number leaves the device. Returns the product, or `nil`.
    func product(barcode: String) async throws -> OpenFoodFactsMatch?
}

/// Failures the caller treats as "no match" (never fatal; the router continues to Sonar).
enum OpenFoodFactsError: Error, Equatable, Sendable {
    case network
    case http(status: Int)
    case decoding
}

/// `OpenFoodFactsClient` over the public v2 API. No auth or key, just a descriptive User-Agent (OFF
/// asks for one). Requests only the fields we map, keeping the response small.
struct HTTPOpenFoodFactsClient: OpenFoodFactsClient {
    private let session: URLSession
    private let host = "world.openfoodfacts.org"
    /// Only the fields we map, to minimize the payload (data minimization, even for non-PHI).
    private static let fields = "product_name,brands,serving_size,serving_quantity,nutriments,code"

    init(session: URLSession = .shared) {
        self.session = session
    }

    func searchProduct(query: String) async throws -> OpenFoodFactsMatch? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        var components = URLComponents()
        components.scheme = "https"
        components.host = host
        components.path = "/api/v2/search"
        components.queryItems = [
            URLQueryItem(name: "search_terms", value: trimmed),
            URLQueryItem(name: "fields", value: Self.fields),
            URLQueryItem(name: "page_size", value: "5"),
            URLQueryItem(name: "nutriment_0", value: "energy-kcal"),
        ]
        guard let url = components.url else { return nil }

        let response: SearchResponse = try await get(url)
        let queryTokens = Self.significantTokens(trimmed)
        for product in response.products {
            guard let match = Self.match(from: product, barcode: nil) else { continue }
            if Self.isRelevant(name: match.item.name, queryTokens: queryTokens) { return match }
        }
        return nil
    }

    /// Significant lowercase tokens for relevance matching: letters-only, ≥4 chars, minus common
    /// filler so a shared filler word ("with", "organic") never counts as a match.
    private static func significantTokens(_ s: String) -> Set<String> {
        Set(
            s.lowercased()
                .split { !$0.isLetter }
                .map(String.init)
                .filter { $0.count >= 4 && !stopWords.contains($0) }
        )
    }

    private static let stopWords: Set<String> = [
        "with", "and", "the", "from", "organic", "fresh", "style", "half", "side", "your", "this",
        "plain", "natural", "homemade", "large", "small", "medium", "plus", "extra",
    ]

    /// A product is relevant only if its name shares at least one significant token with the query.
    private static func isRelevant(name: String, queryTokens: Set<String>) -> Bool {
        guard !queryTokens.isEmpty else { return false }
        return !significantTokens(name).isDisjoint(with: queryTokens)
    }

    func product(barcode: String) async throws -> OpenFoodFactsMatch? {
        let code = barcode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !code.isEmpty, code.allSatisfy(\.isNumber) else { return nil }

        var components = URLComponents()
        components.scheme = "https"
        components.host = host
        components.path = "/api/v2/product/\(code)"
        components.queryItems = [URLQueryItem(name: "fields", value: Self.fields)]
        guard let url = components.url else { return nil }

        let response: ProductResponse = try await get(url)
        guard response.status == 1, let product = response.product else { return nil }
        return Self.match(from: product, barcode: code)
    }

    private func get<T: Decodable>(_ url: URL) async throws -> T {
        var request = URLRequest(url: url)
        request.setValue("Gains/0.1 (private health app)", forHTTPHeaderField: "User-Agent")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw OpenFoodFactsError.network
        }
        guard let http = response as? HTTPURLResponse else { throw OpenFoodFactsError.network }
        guard (200..<300).contains(http.statusCode) else {
            throw OpenFoodFactsError.http(status: http.statusCode)
        }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw OpenFoodFactsError.decoding
        }
    }

    /// Map an OFF product row to our match, or `nil` if it lacks a usable name/calories. OFF nutriments
    /// are per 100g; if the product declares a serving quantity we scale to one serving so the logged
    /// number matches what a person eats, otherwise we keep per-100g and note it in the assumptions.
    private static func match(from product: Product, barcode: String?) -> OpenFoodFactsMatch? {
        let rawName = product.productName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let brand = product.brands?.split(separator: ",").first.map(String.init)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let name: String
        if !rawName.isEmpty, let brand, !brand.isEmpty, !rawName.localizedStandardContains(brand) {
            name = "\(brand) \(rawName)"
        } else if !rawName.isEmpty {
            name = rawName
        } else if let brand, !brand.isEmpty {
            name = brand
        } else {
            return nil
        }

        let n = product.nutriments
        guard let kcalPer100 = n?.energyKcal100g, kcalPer100 > 0 else { return nil }

        let servingGrams = product.servingQuantity
        let scale = (servingGrams.map { $0 > 0 ? $0 / 100.0 : 1.0 }) ?? 1.0
        let servingDescription = product.servingSize?.trimmingCharacters(in: .whitespacesAndNewlines)

        func scaled(_ value: Double?) -> Double? { value.map { ($0 * scale * 10).rounded() / 10 } }

        let item = LoggedFoodItem(
            name: name,
            calories: (kcalPer100 * scale).rounded(),
            proteinG: scaled(n?.proteins100g) ?? 0,
            carbsG: scaled(n?.carbohydrates100g) ?? 0,
            fatG: scaled(n?.fat100g) ?? 0,
            sugarG: scaled(n?.sugars100g),
            fiberG: scaled(n?.fiber100g),
            sodiumMg: scaled(n?.sodium100g).map { $0 * 1000 },
            citations: ["https://world.openfoodfacts.org/product/\(product.code ?? barcode ?? "")"],
            assumptions: "Matched from Open Food Facts"
                + (servingGrams != nil ? " (scaled to one serving)." : " (per 100 g)."),
            confidenceScore: 80
        )
        return OpenFoodFactsMatch(
            item: item,
            servingDescription: servingDescription?.isEmpty == false ? servingDescription : nil,
            barcode: barcode ?? product.code
        )
    }
}

private struct SearchResponse: Decodable {
    let products: [Product]
}

private struct ProductResponse: Decodable {
    let status: Int
    let product: Product?
}

/// Only the fields we requested. All optional: a missing field becomes a nil macro, never a crash.
/// `serving_quantity` may arrive as a number or a numeric string, so we decode it tolerantly.
private struct Product: Decodable {
    let productName: String?
    let brands: String?
    let servingSize: String?
    let servingQuantity: Double?
    let nutriments: Nutriments?
    let code: String?

    enum CodingKeys: String, CodingKey {
        case productName = "product_name"
        case brands
        case servingSize = "serving_size"
        case servingQuantity = "serving_quantity"
        case nutriments
        case code
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        productName = try c.decodeIfPresent(String.self, forKey: .productName)
        brands = try c.decodeIfPresent(String.self, forKey: .brands)
        servingSize = try c.decodeIfPresent(String.self, forKey: .servingSize)
        nutriments = try c.decodeIfPresent(Nutriments.self, forKey: .nutriments)
        code = try c.decodeIfPresent(String.self, forKey: .code)
        if let number = try? c.decodeIfPresent(Double.self, forKey: .servingQuantity) {
            servingQuantity = number
        } else if let string = try? c.decodeIfPresent(String.self, forKey: .servingQuantity) {
            servingQuantity = Double(string)
        } else {
            servingQuantity = nil
        }
    }
}

/// OFF nutriment fields are per 100g.
private struct Nutriments: Decodable {
    let energyKcal100g: Double?
    let proteins100g: Double?
    let carbohydrates100g: Double?
    let fat100g: Double?
    let sugars100g: Double?
    let fiber100g: Double?
    let sodium100g: Double?

    enum CodingKeys: String, CodingKey {
        case energyKcal100g = "energy-kcal_100g"
        case proteins100g = "proteins_100g"
        case carbohydrates100g = "carbohydrates_100g"
        case fat100g = "fat_100g"
        case sugars100g = "sugars_100g"
        case fiber100g = "fiber_100g"
        case sodium100g = "sodium_100g"
    }
}
