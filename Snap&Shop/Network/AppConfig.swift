import Foundation

enum AppConfig {
    static let backendBaseURL: URL = {
        guard
            var raw = Bundle.main.infoDictionary?["BackendBaseURL"] as? String,
            !raw.isEmpty
        else {
            fatalError("BackendBaseURL missing from Info.plist — check xcconfig wiring")
        }
        // xcconfig cannot contain // (treated as comment) so Xcode writes https:/$()/host.
        // $() expands to empty string → https:///host. Normalise to a valid https:// URL.
        raw = raw.replacingOccurrences(of: "///", with: "//")
        guard let url = URL(string: raw) else {
            fatalError("BackendBaseURL is not a valid URL after normalisation: \(raw)")
        }
        return url
    }()
}
