import Foundation

enum WhoopDevice {
    /// Whoop's app API base URL.
    static let apiBase = "https://api.prod.whoop.com"

    /// Every data URL gets `?apiVersion=7`, the version the iOS app pins.
    static let apiVersion = "7"

    /// Abort a data request that stalls past this, so a hung socket can't wedge a fetch.
    static let requestTimeout: TimeInterval = 30

    private static let iosAppVersion = "5.52.0"
    private static let iosBuildNumber = "595097"
    private static let iosBundleName = "com.whoop.iphone"

    /// The device's IANA time zone (e.g. "America/Los_Angeles"), for `x-whoop-time-zone`.
    /// Falls back to a common zone when the device's identifier isn't IANA-shaped. The
    /// header must be present and IANA-shaped to match the app.
    private static func deviceTimeZone() -> String {
        let id = TimeZone.current.identifier
        return id.contains("/") ? id : "America/Los_Angeles"
    }

    /// The identity headers the WHOOP iOS app stamps on every data request, minus the per-request
    /// telemetry (Sentry baggage/trace) and marketing cookies that carry no auth weight.
    ///
    /// `authorization` (and `content-type` for write bodies) is layered on by the caller, not here.
    /// `accept-encoding` is deliberately unset: setting it manually can disable URLSession's
    /// automatic response decompression and break JSON decoding.
    ///
    /// - Parameter installationId: the stable per-install UUID from WhoopTokenStore.
    static func headers(installationId: String) -> [String: String] {
        [
            "user-agent": "iOS",
            "x-whoop-device-platform": "iOS",
            "x-whoop-ios-version": iosAppVersion,
            "x-whoop-ios-build-number": iosBuildNumber,
            "x-whoop-bundle-name": iosBundleName,
            "x-whoop-installation-identifier": installationId,
            "x-whoop-time-zone": deviceTimeZone(),
            "x-whoop-clock-format": "TWELVE_HOUR",
            "currency": "USD",
            "locale": "en_US",
            "accept-language": "en",
            "accept": "*/*",
            "priority": "u=3",
        ]
    }

    /// Build a data-endpoint URL with the pinned `apiVersion` and any extra query
    /// params. `path` is a leading-slash path like "/home-service/v1/home". Returns nil
    /// only if the base + path can't form a URL (never in practice).
    static func dataURL(path: String, query: [String: String] = [:]) -> URL? {
        guard var components = URLComponents(string: apiBase + path) else { return nil }
        var items = [URLQueryItem(name: "apiVersion", value: apiVersion)]
        for (k, v) in query { items.append(URLQueryItem(name: k, value: v)) }
        components.queryItems = items
        return components.url
    }
}
