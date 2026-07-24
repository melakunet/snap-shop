import Foundation

enum AppConfig {
    static let backendBaseURL: URL = {
        guard
            let raw = Bundle.main.infoDictionary?["BackendBaseURL"] as? String,
            !raw.isEmpty,
            let url = URL(string: raw)
        else {
            fatalError("BackendBaseURL missing or invalid in Info.plist — check xcconfig")
        }
        return url
    }()
}
