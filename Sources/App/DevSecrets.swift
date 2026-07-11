#if DEBUG
import Foundation

/// DEBUG-only developer convenience: an optional OpenRouter key seeded into the Keychain on a fresh
/// simulator so the AI food-logging lanes work without pasting a key in Settings. Empty by default
/// (the seed step no-ops); drop in your own key locally. Never commit a real key.
enum DevSecrets {
    static let openRouterKey = ""
}
#endif
