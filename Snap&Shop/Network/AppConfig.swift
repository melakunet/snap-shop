import Foundation

enum AppConfig {
    // Canonical backend URL. xcconfig cannot contain // (treated as comment), so the
    // xcconfig value uses https:/$()/host — $() expands to empty string at build time,
    // producing https:///host in the plist, which we normalise below.
    // On "My Mac (Designed for iPad)" the $() substitution sometimes misfires and leaves
    // the value empty or unexpanded; the hardcoded fallback ensures the app never crashes.
    /// Set to true only after adding iCloud capability + CloudKit entitlement (requires paid team).
    static let iCloudSyncEnabled = false

    static let backendBaseURL: URL = {
        let fallback = URL(string: "https://snap-shop-api-dev.etefmelaku.workers.dev")!
        guard
            var raw = Bundle.main.infoDictionary?["BackendBaseURL"] as? String,
            !raw.isEmpty,
            !raw.hasPrefix("$(")   // unexpanded build variable — treat as missing
        else {
            return fallback
        }
        raw = raw.replacingOccurrences(of: "///", with: "//")
        return URL(string: raw) ?? fallback
    }()
}
