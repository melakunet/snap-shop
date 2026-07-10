import Foundation

enum AppConfig {
    // Development: plain HTTP to wrangler dev on the Mac.
    // Simulator: covered by NSAllowsLocalNetworking (use http://localhost:8787).
    // Real device on LAN: NSExceptionDomains in Info.plist covers this IP.
    // DEV ONLY — remove NSExceptionDomains from Info.plist and switch to HTTPS before production:
    //   static let backendBaseURL = URL(string: "https://api.snapshop.app")!
    static let backendBaseURL = URL(string: "http://192.168.2.12:8787")!
}
