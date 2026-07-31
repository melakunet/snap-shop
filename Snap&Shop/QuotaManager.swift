import Foundation

/// Tracks free-tier Precision scan usage with a monthly rolling window.
/// Pro users bypass all quota checks; this manager is only consulted for
/// non-Pro sessions.
enum QuotaManager {
    static let freeLimit = 10

    private static let kCount = "quota_precision_count"
    private static let kMonth = "quota_precision_month"

    /// Returns true when the user has scans remaining this month.
    static func canScan() -> Bool {
        rolloverIfNeeded()
        return UserDefaults.standard.integer(forKey: kCount) < freeLimit
    }

    /// Number of Precision scans used this calendar month.
    static func scansUsed() -> Int {
        rolloverIfNeeded()
        return UserDefaults.standard.integer(forKey: kCount)
    }

    /// Increments the scan counter. Call once per initiated Precision scan.
    static func recordScan() {
        rolloverIfNeeded()
        let n = UserDefaults.standard.integer(forKey: kCount)
        UserDefaults.standard.set(n + 1, forKey: kCount)
    }

    /// Resets quota state. Only called from the DEBUG Settings panel.
    static func resetForDebug() {
        UserDefaults.standard.removeObject(forKey: kCount)
        UserDefaults.standard.removeObject(forKey: kMonth)
    }

    // Resets the count when the calendar month turns over.
    private static func rolloverIfNeeded() {
        let comps = Calendar.current.dateComponents([.year, .month], from: Date())
        let tag = "\(comps.year ?? 0)-\(comps.month ?? 0)"
        if UserDefaults.standard.string(forKey: kMonth) != tag {
            UserDefaults.standard.set(tag, forKey: kMonth)
            UserDefaults.standard.set(0, forKey: kCount)
        }
    }
}
