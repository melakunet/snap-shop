import Foundation

/// Single source of truth for retailer-selection preferences.
/// SettingsView uses `RetailerPrefs.all` for display; every /shop call
/// reads `RetailerPrefs.whitelist(from:)` to build the filter array.
enum RetailerPrefs {

    static let userDefaultsKey = "retailerSelectionCSV"

    struct Entry {
        let name: String
        let icon: String    // SF Symbol name
    }

    static let all: [Entry] = [
        Entry(name: "Amazon",     icon: "cart.fill"),
        Entry(name: "Walmart",    icon: "bag.fill"),
        Entry(name: "Best Buy",   icon: "tv.fill"),
        Entry(name: "eBay",       icon: "tag.fill"),
        Entry(name: "Target",     icon: "scope"),
        Entry(name: "Home Depot", icon: "hammer.fill"),
        Entry(name: "B&H",        icon: "camera.fill"),
    ]

    static let allNames: Set<String> = Set(all.map(\.name))

    /// Decode a CSV string into the enabled set.
    /// Empty string (the default) → all retailers enabled.
    static func enabledRetailers(from csv: String) -> Set<String> {
        csv.isEmpty ? allNames : Set(csv.split(separator: ",").map(String.init))
    }

    /// Encode an enabled set back to CSV.
    /// Full set → empty string so the default state round-trips cleanly.
    static func csv(from enabled: Set<String>) -> String {
        enabled == allNames ? "" : enabled.sorted().joined(separator: ",")
    }

    /// Whitelist array to pass to /shop.
    /// Empty array → backend applies no filtering (all sources pass through).
    static func whitelist(from csv: String) -> [String] {
        let enabled = enabledRetailers(from: csv)
        guard !enabled.isEmpty, enabled != allNames else { return [] }
        return Array(enabled)
    }
}
