import Foundation

enum AppConfig {
    // Development: plain HTTP to local wrangler dev server.
    // ATS exception NSAllowsLocalNetworking in Info.plist covers this URL.
    // TODO: switch to production HTTPS URL before App Store submission:
    //   static let backendBaseURL = URL(string: "https://api.snapshop.app")!
    static let backendBaseURL = URL(string: "http://localhost:8787")!
}
