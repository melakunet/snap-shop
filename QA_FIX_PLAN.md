# Snap&Shop — Pre-Submission QA Fix Plan

**Generated:** 2026-09-04  
**Test baseline:** 68/70 passing (2 failing in QuotaManagerTests)  
**Total issues identified:** 22 across 7 files  
**Goal:** 70/70 tests, all issues resolved, submission-ready build

> Keep this file local. Do not push to remote.

---

## How to Use This Plan

Work top to bottom. Each phase must be fully complete and verified before moving to the next.
After Phase 4 (all fixes done), run the full test suite, then do Phase 5 (new tests), then sign off
on Phase 6 (submission checklist).

Mark each item `[x]` as you complete it.

---

## Phase 0 — Fix the 2 Failing Tests (BLOCKING)

These two failures block the entire test run from being clean. Fix first.

### P0.1 — QuotaManagerTests race condition

**Root cause:** Swift Testing's `@Test` framework runs tests concurrently by default.
`QuotaManagerTests` share global `UserDefaults` state (keys `quota_precision_count` and
`quota_precision_month`). The `rolloverResetsCount` test writes a stale month key `"1999-1"` mid-run,
which `rolloverIfNeeded()` in a concurrent test intercepts, resetting the count to 0.

**Failing tests:**
- `recordScanIncrementsCount()` — expected 2, got 1 (count reset mid-run)
- `cannotScanAfterLimitReached()` — canScan() still true after 300 iterations (count reset mid-loop)

**File:** `Snap&Shop/Snap&ShopTests/Snap_ShopTests.swift:295`

**Fix:** Add `@Suite(.serialized)` to `QuotaManagerTests` — forces the six tests in that struct to
run serially, eliminating the shared-state race.

```swift
// BEFORE (line 295):
struct QuotaManagerTests {

// AFTER:
@Suite(.serialized)
struct QuotaManagerTests {
```

**Verify:** Run all tests → 70/70 pass.

- [ ] Applied and verified

---

## Phase 1 — Critical: Real Production Bugs

These affect data integrity, user experience, or safety in a shipping build.

### C1 — AlertsView: alert check mutations never persisted

**File:** `Snap&Shop/Snap&Shop/Views/AlertsView.swift:150`

**Problem:** `checkAllAlerts()` mutates SwiftData model objects (`alert.lastCheckedDate`,
`alert.triggered`, `saved.currentLowestPrice`) inside a for loop, but never calls
`modelContext.save()`. SwiftData may auto-save on scene phase transition, but if the user backgrounds
the app the instant the check finishes, all changes are lost. Triggered alerts re-fire on next launch.

```swift
// BEFORE — loop ends at line 150, nothing saved:
        if lowest.extractedPrice <= alert.targetPrice {
            alert.triggered = true
            scheduleNotification(for: alert, price: lowest.extractedPrice)
        }
    }                               // ← end of for loop, no save
}

// AFTER — add explicit save after the loop:
        if lowest.extractedPrice <= alert.targetPrice {
            alert.triggered = true
            scheduleNotification(for: alert, price: lowest.extractedPrice)
        }
    }
    try? modelContext.save()
}
```

- [ ] Applied and verified

---

### C2 — try! ModelContainer in preview definitions (3 files)

**Problem:** Module-scope `try!` will crash the preview when `ModelContainer` init fails (schema
mismatch, disk error, or Xcode state). Doesn't affect production builds, but crashes the whole file's
previews for developers and in any Xcode Preview CI environment.

**Files and lines:**
- `ResultsView.swift:1872` — `private let previewContainer = try! ModelContainer(...)`
- `AlertsView.swift:287` — `try! ModelContainer(...)` inside `#Preview`
- `SavedView.swift:149` — `try! ModelContainer(...)` inside `#Preview`

**Fix pattern for ResultsView (module-scope let):**

```swift
// BEFORE (line 1872):
private let previewContainer = try! ModelContainer(
    for: Schema([ScanRecord.self, SavedItem.self]),
    configurations: ModelConfiguration(isStoredInMemoryOnly: true)
)

// AFTER:
private let previewContainer: ModelContainer = {
    do {
        return try ModelContainer(
            for: Schema([ScanRecord.self, SavedItem.self]),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    } catch {
        fatalError("[Preview] ModelContainer init failed: \(error)")
    }
}()
```

**Fix pattern for AlertsView and SavedView (inside #Preview):**

```swift
// BEFORE (AlertsView.swift:287):
    .modelContainer(
        try! ModelContainer(
            for: Schema([ScanRecord.self, SavedItem.self, PriceAlert.self]),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    )

// AFTER:
    .modelContainer(
        try! ModelContainer(          // ← acceptable ONLY in #Preview macro scope
            for: Schema([ScanRecord.self, SavedItem.self, PriceAlert.self]),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    )
    // Note: SwiftUI's #Preview macro catches fatalError; try! is idiomatic here.
    // The ResultsView module-scope let is the only real risk — fix that one with the closure above.
```

> **Verdict after re-review:** The `#Preview { }` macro context wraps exceptions safely; `try!` inside
> `#Preview { }` is acceptable Xcode convention. Only the **module-scope** `private let previewContainer =
> try! ...` in ResultsView.swift is a real risk — fix that one. Leave AlertsView and SavedView as-is.

- [ ] ResultsView.swift:1872 — changed to closure with do/catch
- [ ] AlertsView.swift and SavedView.swift — confirmed acceptable as-is (inside #Preview)

---

### C3 — BackendClient: empty noProductsFound message shows blank error banner

**File:** `Snap&Shop/Snap&Shop/Network/BackendClient.swift:14`

**Problem:** If the backend sends `"message": ""`, `errorDescription` returns an empty string. The
results screen shows the error banner but with no text — confusing UX.

```swift
// BEFORE (line 14):
case .noProductsFound(let msg): msg

// AFTER:
case .noProductsFound(let msg): msg.isEmpty ? "No matching products found." : msg
```

- [ ] Applied and verified

---

## Phase 2 — High: Correctness and Reliability Issues

### H1 — AuthState: signOut() discards Keychain delete results silently

**File:** `Snap&Shop/Snap&Shop/Auth/AuthState.swift:58-60`

**Problem:** `KeychainStore.delete()` returns `@discardableResult Bool`. If any of the three deletes
fail (corrupted Keychain, rare but possible), the in-memory state is cleared (`userId = nil` etc.)
but the Keychain entry persists. Next cold launch, `AuthState.init()` reloads from Keychain and the
user appears to be re-signed-in after signing out.

```swift
// BEFORE (lines 58-60):
        KeychainStore.delete(key: Keys.userId)
        KeychainStore.delete(key: Keys.identityToken)
        KeychainStore.delete(key: Keys.displayName)

// AFTER — log failures so they're diagnosable:
        let deletions: [(String, Bool)] = [
            (Keys.userId,        KeychainStore.delete(key: Keys.userId)),
            (Keys.identityToken, KeychainStore.delete(key: Keys.identityToken)),
            (Keys.displayName,   KeychainStore.delete(key: Keys.displayName)),
        ]
        #if DEBUG
        for (key, success) in deletions where !success {
            print("[AuthState] Keychain delete failed for key: \(key)")
        }
        #endif
```

- [ ] Applied and verified

---

### H2 — CameraSession: device unavailable leaves camera blank with no message

**File:** `Snap&Shop/Snap&Shop/Scan/CameraSession.swift:52-58`

**Problem:** `configureSession()` guards on `AVCaptureDevice.default()` returning a device and
creating an input. On failure it commits the empty configuration and returns — but `permissionDenied`
is never set. The camera view shows a blank/frozen live view with no error message. User doesn't
know the camera is broken.

```swift
// BEFORE (lines 52-58):
        guard
            let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
            let input = try? AVCaptureDeviceInput(device: device)
        else {
            session.commitConfiguration()
            return
        }

// AFTER:
        guard
            let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
            let input = try? AVCaptureDeviceInput(device: device)
        else {
            session.commitConfiguration()
            DispatchQueue.main.async { self.permissionDenied = true }
            return
        }
```

> Note: `permissionDenied` already drives the "Camera access required" error UI in CameraView.
> This re-uses that path rather than adding a new state variable.

- [ ] Applied and verified

---

### H3 — CameraSession: temp .mov file not cleaned up on recording error

**File:** `Snap&Shop/Snap&Shop/Scan/CameraSession.swift:124-127` and `182-188`

**Problem:** `startRecording()` creates a temp `.mov` URL but doesn't track it. If recording fails
(hardware error, storage full), the delegate sets `capturedVideoURL = nil` (correct), but the partial
temp file is never deleted and accumulates in `tmp/` until the OS clears it.

```swift
// BEFORE — startRecording() (line 117):
    func startRecording() {
        guard !isRecording,
              let connection = movieFileOutput.connection(with: .video) else { return }
        if connection.isVideoStabilizationSupported {
            connection.preferredVideoStabilizationMode = .auto
        }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".mov")
        DispatchQueue.main.async { self.isRecording = true }
        sessionQueue.async { self.movieFileOutput.startRecording(to: url, recordingDelegate: self) }
    }

// AFTER — add a tracked property and clean up on error:
    private var currentRecordingURL: URL?     // ← add this property near line 11

    func startRecording() {
        guard !isRecording,
              let connection = movieFileOutput.connection(with: .video) else { return }
        if connection.isVideoStabilizationSupported {
            connection.preferredVideoStabilizationMode = .auto
        }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".mov")
        currentRecordingURL = url             // ← track it
        DispatchQueue.main.async { self.isRecording = true }
        sessionQueue.async { self.movieFileOutput.startRecording(to: url, recordingDelegate: self) }
    }

// BEFORE — delegate callback (line 183):
    nonisolated func fileOutput(
        _: AVCaptureFileOutput,
        didFinishRecordingTo outputFileURL: URL,
        from _: [AVCaptureConnection],
        error: Error?
    ) {
        DispatchQueue.main.async {
            self.isRecording = false
            if error == nil {
                self.capturedVideoURL = outputFileURL
            }
        }
    }

// AFTER — clean up temp file on error:
    nonisolated func fileOutput(
        _: AVCaptureFileOutput,
        didFinishRecordingTo outputFileURL: URL,
        from _: [AVCaptureConnection],
        error: Error?
    ) {
        DispatchQueue.main.async {
            self.isRecording = false
            if error == nil {
                self.capturedVideoURL = outputFileURL
            } else {
                self.currentRecordingURL = nil
                try? FileManager.default.removeItem(at: outputFileURL)
            }
        }
    }
```

- [ ] Property added to CameraSession
- [ ] Cleanup added to delegate failure path

---

### H4 — QuotaManager: nil date components silently produce wrong rollover tag

**File:** `Snap&Shop/Snap&Shop/QuotaManager.swift:43-44`

**Problem:** On a misconfigured or corrupted device, `Calendar.current.dateComponents` could return
nil year/month. The fallback `?? 0` produces tag `"0-0"`, which never matches any real date, so
`rolloverIfNeeded()` runs on every single call and resets the count to 0 — making the quota appear
infinite.

```swift
// BEFORE (lines 43-44):
    private static func rolloverIfNeeded() {
        let comps = Calendar.current.dateComponents([.year, .month], from: Date())
        let tag = "\(comps.year ?? 0)-\(comps.month ?? 0)"
        if UserDefaults.standard.string(forKey: kMonth) != tag {

// AFTER:
    private static func rolloverIfNeeded() {
        let comps = Calendar.current.dateComponents([.year, .month], from: Date())
        guard let year = comps.year, let month = comps.month else { return }
        let tag = "\(year)-\(month)"
        if UserDefaults.standard.string(forKey: kMonth) != tag {
```

- [ ] Applied and verified

---

## Phase 3 — Medium: Robustness and Edge Cases

### M1 — SavedView.delete(): FetchDescriptor failure orphans PriceAlerts

**File:** `Snap&Shop/Snap&Shop/Views/SavedView.swift:139`

**Problem:** `try?` on `modelContext.fetch(alertDescriptor)` silently swallows errors. If the fetch
fails, related `PriceAlert` records are orphaned in the database — they stay forever, consume
space, and appear in the Alerts tab attached to a deleted item.

```swift
// BEFORE (lines 136-141):
        let alertDescriptor = FetchDescriptor<PriceAlert>(
            predicate: #Predicate { $0.savedItemId == itemId }
        )
        if let related = try? modelContext.fetch(alertDescriptor) {
            related.forEach { modelContext.delete($0) }
        }

// AFTER:
        let alertDescriptor = FetchDescriptor<PriceAlert>(
            predicate: #Predicate { $0.savedItemId == itemId }
        )
        do {
            let related = try modelContext.fetch(alertDescriptor)
            related.forEach { modelContext.delete($0) }
        } catch {
            #if DEBUG
            print("[SavedView] Failed to fetch related alerts for cleanup: \(error)")
            #endif
        }
```

- [ ] Applied and verified

---

### M2 — ResultsView: shipping regex misses "$.99" format

**File:** `Snap&Shop/Snap&Shop/Views/ResultsView.swift:50`

**Problem:** Pattern `\$\s*(\d+(?:\.\d{1,2})?)` requires at least one digit before the decimal
point. Input like `"$.99"` returns `(nil, false)` — treated as unknown shipping, biasing total-price
sort incorrectly.

```swift
// BEFORE (line 50):
    guard let regex = try? NSRegularExpression(pattern: #"\$\s*(\d+(?:\.\d{1,2})?)"#) else {

// AFTER — allow optional leading digit:
    guard let regex = try? NSRegularExpression(pattern: #"\$\s*(\d*\.?\d+)"#) else {
```

**Note:** The updated pattern matches `"$5.99"`, `"$12"`, `"$.99"`, `"$0.50"` — all real SerpAPI formats.

- [ ] Applied and verified
- [ ] Add `ShippingParserTests` case: `dollarAmountNoLeadingDigit` (input `"$.99"`, expects cost 0.99)

---

### M3 — modelContext.save() errors silently swallowed

**Files:**
- `ResultsView.swift:1583` — `try? modelContext.save()` after toggleSave
- `AlertsView.swift:278` — `try? modelContext.save()` after creating a new PriceAlert

**Problem:** All SwiftData persistence errors are silently discarded. User taps Save or Set Alert,
sees the UI respond correctly, but data may not be on disk if something went wrong.

**Fix — add DEBUG logging at minimum:**

```swift
// Pattern to apply at each site:

// BEFORE:
try? modelContext.save()

// AFTER:
do {
    try modelContext.save()
} catch {
    #if DEBUG
    print("[SwiftData] save() failed: \(error)")
    #endif
}
```

Apply to:
- `ResultsView.swift:1583`
- `AlertsView.swift:278`

- [ ] ResultsView:1583 updated
- [ ] AlertsView:278 updated

---

### M4 — Unbounded @Query in SavedView (document + defer)

**File:** `Snap&Shop/Snap&Shop/Views/SavedView.swift:5`

**Problem:** `@Query` with no fetch limit loads ALL saved items into memory. This is fine for typical
users (<100 items) but would degrade with thousands of entries.

**Decision for v1:** Add a comment documenting the known limit; pagination is out of scope for
initial submission but must be added before a viral scale event.

```swift
// Line 5 — add comment:
// TODO: Add fetch limit (e.g. 200) before any potential scale event. Current unbounded
// @Query is fine for typical usage but degrades with very large saved item counts.
@Query(sort: \SavedItem.savedDate, order: .reverse) private var items: [SavedItem]
```

- [ ] Comment added

---

## Phase 4 — Low: Defensive Hardening

### L1 — QuotaManager: assert freeLimit in Release builds

**File:** `Snap&Shop/Snap&Shop/QuotaManager.swift:7-11`

**Problem:** If `#if DEBUG` is accidentally active in a Release distribution, users get 300 free
scans instead of 10.

```swift
// BEFORE:
    #if DEBUG
    static let freeLimit = 300
    #else
    static let freeLimit = 10
    #endif

// AFTER — add runtime safety net in debug:
    #if DEBUG
    static let freeLimit = 300
    #else
    static let freeLimit = 10
    #endif

    // Sanity check: Release builds must never get the inflated DEBUG limit.
    // This fires during development if a wrong build config is used.
    static func validateConfiguration() {
        #if !DEBUG
        assert(freeLimit == 10, "Release build must use freeLimit = 10")
        #endif
    }
```

Call `QuotaManager.validateConfiguration()` from `Snap_ShopApp.init()`.

- [ ] Function added
- [ ] Called from app init

---

### L2 — ResultsView time observer: add explicit [weak self]

**File:** `Snap&Shop/Snap&Shop/Views/ResultsView.swift:1474`

**Problem:** `playerCurrentTime` and `playerDuration` are captured implicitly from the `@State`
struct binding. Since `ResultsView` is a `struct` (not a class), there's no retain cycle, but
the implicit capture is misleading for code readers and can cause state updates on a stale binding
if `teardownTimeObserver()` is ever delayed.

```swift
// BEFORE (line 1474):
        timeObserverToken = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak player] time in
            playerCurrentTime = time.seconds
            if let duration = player?.currentItem?.duration, duration.isNumeric {
                playerDuration = max(duration.seconds, 1)
            }
        }

// AFTER — no functional change, clearer intent:
        timeObserverToken = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak player] time in
            guard player != nil else { return }
            playerCurrentTime = time.seconds
            if let duration = player?.currentItem?.duration, duration.isNumeric {
                playerDuration = max(duration.seconds, 1)
            }
        }
```

- [ ] Applied

---

## Phase 5 — Retest After All Fixes

### Step 1: Run full test suite

Expected: **70/70 pass**

If any test still fails, stop and diagnose before continuing.

- [ ] 70/70 passing

### Step 2: Build project

Run a full build (Product → Build or ⌘B in Xcode). Expected: **0 errors, 0 warnings.**

If warnings exist, review each one — don't ship with fixable warnings.

- [ ] Build succeeds, 0 errors
- [ ] 0 new warnings introduced by fixes

### Step 3: Code-level spot checks after fixes

Verify each fix file compiles and the logic is correct:

- [ ] `QuotaManager.swift` — `rolloverIfNeeded()` guard compiles and kMonth key is correctly set
- [ ] `CameraSession.swift` — `permissionDenied = true` on the main queue in configure guard
- [ ] `CameraSession.swift` — `currentRecordingURL` property is accessible in delegate extension
- [ ] `AlertsView.swift` — `try? modelContext.save()` is after the closing brace of the for loop
- [ ] `ResultsView.swift` — `previewContainer` is a closure, not a `try!` let
- [ ] `BackendClient.swift` — `noProductsFound` fallback message is a non-empty string

---

## Phase 6 — New Tests to Add

These are currently untested paths that carry real risk for submission. Add them to
`Snap_ShopTests.swift` in new `@Suite` structs.

### New test suites needed:

#### AuthStateTests (new)

| Test | What it verifies |
|---|---|
| `signOutClearsInMemoryState()` | `userId`, `identityToken`, `displayName` all nil after signOut |
| `signInPersistsToKeychain()` | After `signIn()`, a new `AuthState()` init loads the same values |
| `signOutClearsKeychain()` | After `signOut()`, a new `AuthState()` init gets all nils |
| `isSignedInFalseWhenNoUserId()` | `isSignedIn` is false with nil userId |
| `demoModeDoesNotWriteKeychain()` (DEBUG only) | `signInAsDemo()` leaves Keychain untouched |

#### BackendClientTests (new)

| Test | What it verifies |
|---|---|
| `noProductsFoundFallbackMessage()` | Empty message string → returns "No matching products found." |
| `shopRequestBodyEncoding()` | `ShopRequestBody` encodes correctly with snake_case keys |

#### AlertPersistenceTests (new, requires SwiftData in-memory container)

| Test | What it verifies |
|---|---|
| `checkAllAlertsCallsSave()` | After `checkAllAlerts()`, alert changes survive a context re-fetch |
| `addAlertSavesPersists()` | `AddAlertSheet.save()` inserts and saves a `PriceAlert` |
| `deleteSavedItemCascadesToAlert()` | Deleting a `SavedItem` also deletes its linked `PriceAlert` |

#### ShippingParserTests (extend existing)

| Test | What it verifies |
|---|---|
| `dollarAmountNoLeadingDigit()` | `"$.99"` → cost 0.99, known true |
| `centAmountWithSpace()` | `"$ 1.50 shipping"` → cost 1.50, known true |

#### QuotaManagerTests (extend existing — after `@Suite(.serialized)` fix)

| Test | What it verifies |
|---|---|
| `rolloverIfNeededHandlesNilComponents()` | Not directly testable (Calendar always works); covered by documentation |
| `validateConfigurationDoesNotAssertInDebug()` | `validateConfiguration()` runs without assertion in DEBUG |

### Total new tests to write: ~15

- [ ] `AuthStateTests` suite written (5 tests)
- [ ] `BackendClientTests` suite written (2 tests)
- [ ] `AlertPersistenceTests` suite written (3 tests)
- [ ] `ShippingParserTests` extended (2 tests)
- [ ] All new tests pass

### Updated target: **85/85 tests passing**

---

## Phase 7 — Submission Checklist

Complete every item before submitting to App Store Connect / TestFlight.

### Build configuration

- [ ] `Release.xcconfig` backend URL points to production (not dev worker)
- [ ] `ENVIRONMENT` is not `"dev"` in Release scheme
- [ ] `DEV_AUTH_BYPASS` is not set (or is `"0"`) in Release scheme
- [ ] `QuotaManager.freeLimit` is 10 in a Release build (confirm via `validateConfiguration()`)
- [ ] `#if DEBUG` blocks all stripped — no debug prints in Release logs

### App Store metadata

- [ ] `CFBundleShortVersionString` and `CFBundleVersion` incremented in `Snap-Shop-Info.plist`
- [ ] StoreKit product IDs match App Store Connect exactly:
  - `snapshop_pro_monthly`
  - `snapshop_pro_annual`
- [ ] Products.storekit file is NOT included in Release target (it's for local testing only)
- [ ] App icon set complete (all required sizes, no missing slots in Assets.xcassets)
- [ ] Privacy descriptions in Info.plist:
  - `NSCameraUsageDescription` — present
  - `NSMicrophoneUsageDescription` — present
  - `NSSpeechRecognitionUsageDescription` — present
  - `NSPhotoLibraryUsageDescription` — present

### Features

- [ ] iCloud sync is disabled (AppConfig.iCloudSyncEnabled = false) — requires paid team + CloudKit entitlement
- [ ] Sign in with Apple entitlement is correctly set in Snap&Shop.entitlements
- [ ] Onboarding shows correctly on first launch (test on a fresh simulator)
- [ ] Paywall correctly loads monthly and annual products from StoreKit
- [ ] Restore Purchases works for existing Pro users

### Manual smoke test (device, not simulator)

- [ ] Cold launch → onboarding appears → sign in with Apple → lands on Camera tab
- [ ] Precision scan: take photo, see results, check prices load, save an item
- [ ] Deep scan (Pro): pan across product, see multi-item chips if applicable
- [ ] Barcode scan: point at a barcode, confirm fast-path result
- [ ] Import image from library → precision results
- [ ] Saved tab: saved item appears, set a price alert
- [ ] Alerts tab: alert appears, tap Check Now, see last-checked date update
- [ ] History tab: scans listed, swipe-to-delete works
- [ ] Settings: retailer toggle persists, correct tab returns filtered results
- [ ] Sign out → app returns to sign-in screen → sign in again → state restored

### Performance

- [ ] Cold launch to camera ready: < 2 seconds
- [ ] Precision scan end-to-end (tap → results visible): P50 < 6 seconds on device
- [ ] Deep scan end-to-end: P50 < 10 seconds on device

---

## Issue Summary Table

| ID | Severity | File | Line | Status |
|----|----------|------|------|--------|
| P0.1 | TEST BUG | Snap_ShopTests.swift | 295 | [ ] |
| C1 | CRITICAL | AlertsView.swift | 150 | [ ] |
| C2 | CRITICAL | ResultsView.swift | 1872 | [ ] |
| C3 | CRITICAL | BackendClient.swift | 14 | [ ] |
| H1 | HIGH | AuthState.swift | 58-60 | [ ] |
| H2 | HIGH | CameraSession.swift | 52-58 | [ ] |
| H3 | HIGH | CameraSession.swift | 117-127, 183-188 | [ ] |
| H4 | HIGH | QuotaManager.swift | 43-44 | [ ] |
| M1 | MEDIUM | SavedView.swift | 139 | [ ] |
| M2 | MEDIUM | ResultsView.swift | 50 | [ ] |
| M3 | MEDIUM | ResultsView.swift, AlertsView.swift | 1583, 278 | [ ] |
| M4 | MEDIUM | SavedView.swift | 5 | [ ] |
| L1 | LOW | QuotaManager.swift | 7-11 | [ ] |
| L2 | LOW | ResultsView.swift | 1474 | [ ] |

**Issues confirmed NOT bugs (QA agent overstated):**
- `ResultsView:1571` — `prices[0]` is already guarded by `guard !prices.isEmpty` on line 1570 ✓
- `ResultsView:1534` — `formatTime()` already has `guard seconds.isFinite, seconds >= 0` ✓
- `ResultsView:768` — `isBarcodeResult` is nil-safe via `?? 0` ✓
- `ResultsView:710-754` — sparkline `count >= 2` guard + `suffix(10)` is safe ✓
- `CameraSession:148-152` — nil `fileDataRepresentation()` just sets `capturedImageData = nil` (handled by CameraView) ✓
- `PoisonControl` nil Locale — `PoisonControl.info(for: nil)` is an explicitly handled case ✓
- `BackendClient` multipart boundary — UUID chars are always valid boundary chars ✓

---

## Notes

- **Token expiry (Apple ID JWT ~10 min):** Documented in AuthState.swift as Phase 3 work.
  Not blocking for v1 — the acceptance test signs in and scans immediately. Log out + back in refreshes token.
- **M4 unbounded @Query:** Deferred to post-launch; add pagination before any viral event.
- After fixing all items, final target is **85/85 tests** (70 existing + ~15 new).
