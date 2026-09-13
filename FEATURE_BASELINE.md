# Snap & Shop — Feature Baseline
> Android port reference. All statuses verified from source code, not README claims.
> Audited: 2026-09-12

---

## 1. FEATURE INVENTORY

### 1.1 Scanning Inputs

| # | Feature | What it does | Status |
|---|---------|-------------|--------|
| S1 | **Precision Photo Scan** | Camera capture → CropSheet → Groq vision + Apple Vision OCR → prices | WORKING |
| S2 | **Photo Library Import (Precision)** | PhotosPicker → same crop/upload flow as S1; quota-gated | WORKING |
| S3 | **File Import (Precision)** | UIDocumentPickerViewController for image files | WORKING |
| S4 | **Barcode Scan (AVFoundation)** | Live camera detects EAN-13/EAN-8/UPC-E/Code128/Code39/Interleaved2of5/DataMatrix/QR on-device | WORKING |
| S5 | **Barcode → ISBN lookup** | EAN-13 with 978/979 prefix → Google Books + Open Library in parallel | WORKING |
| S6 | **Barcode → Product lookup** | Non-ISBN → Open Food Facts → UPCitemdb (key required) | WORKING |
| S7 | **Deep / Video Scan (Pro)** | 10-second live recording → 5 keyframes @ 384px → Gemini 2.5 Flash (Pro escalate < 0.4) | WORKING |
| S8 | **Video Library Import (Pro)** | PhotosPicker video → same Gemini pipeline | WORKING |
| S9 | **Video File Import (Pro)** | UIDocumentPickerViewController for .mov/.mp4/.m4v | WORKING |
| S10 | **Video Frame Crop** | First frame extracted from video for precision-style scan; CropSheet presented | WORKING |
| S11 | **Voice Hint (Deep)** | Whisper transcribes video audio → hint injected into Gemini prompt; transcript sheet with editable text | WORKING |
| S12 | **Text / Manual Search** | Search bar on camera view → ResultsView(textQuery:) → /shop | WORKING |
| S13 | **Paste-a-Link** | Detects URL in clipboard → chip appears → POST /identify/url → prices | WORKING |

---

### 1.2 Results & Pricing

| # | Feature | What it does | Status |
|---|---------|-------------|--------|
| R1 | **Price card list** | Up to 10 results sorted by total price (item + shipping) or Bayesian review score | WORKING |
| R2 | **Shipping cost parser** | Parses "Free shipping" / "$5.99 shipping" strings into structured total | WORKING |
| R3 | **Trust level badges** | Major retailer (green) / Marketplace (amber) / Unknown (none) | WORKING |
| R4 | **Sort toggle** | "Best price" vs "Best reviewed" — backend re-sorts on selection change | WORKING |
| R5 | **Price sparkline** | Mini line chart of prior scan prices for same query (requires ≥ 2 points from ScanRecord) | WORKING |
| R6 | **Product header card** | Brand, model, category, confidence, image (barcode/URL scans only) | WORKING |
| R7 | **Confidence banners** | Red "BEST GUESS" < 0.35; Amber "Try Deep Scan" 0.35–0.60; none ≥ 0.60 | WORKING |
| R8 | **Deep Scan escalation** | Amber banner → binding propagates hint to CameraView, switches mode to Deep | WORKING |
| R9 | **Multi-item chips (Deep)** | When deep scan finds multiple products, chip row lets user switch between them | WORKING |
| R10 | **ProductDetailView** | Hero image, retailer info, snippet, reviews section, Buy button | WORKING |
| R11 | **Reviews section** | Fetches /product/reviews (Google Shopping product_id); rating breakdown + snippets | WORKING |
| R12 | **Save to favorites** | Bookmark button on price card → SwiftData SavedItem | WORKING |
| R13 | **Empty state (no prices)** | Shows product card + "No prices found" when identification succeeds but prices = [] | WORKING |
| R14 | **VoiceOver labels** | Comprehensive a11y labels on price cards (price, shipping, retailer, trust, rating, best match) | WORKING |
| R15 | **Retailer whitelist filtering** | CSV preference passed as retailer_whitelist to /shop; backend applies filter | WORKING |

---

### 1.3 Plant / Hazard

| # | Feature | What it does | Status |
|---|---------|-------------|--------|
| P1 | **Plant identification** | Groq detects plant-like → specialist pass confirms species, confidence, hazard signals | WORKING |
| P2 | **Danger suppression** | Dangerous plants: search_query cleared → no shopping results shown | WORKING |
| P3 | **Warning banners** | fatal/severe/moderate levels shown with colour-coded note | WORKING |
| P4 | **Safety note** | Berry/mushroom hazard signals add extra safety note even on non-danger plants | WORKING |
| P5 | **Poison Control** | Region-aware phone number/URL (US, Canada, UK, generic fallback); tappable link | WORKING |
| P6 | **plantUnidentified error state** | When specialist returns "unknown" species, clear 422 error shown (no shopping) | WORKING |

---

### 1.4 Persistence

| # | Feature | What it does | Status |
|---|---------|-------------|--------|
| D1 | **Scan history** | SwiftData ScanRecord: date, product name, mode badge, lowest price, thumbnail (external storage) | WORKING |
| D2 | **History search** | Searchable by product name (case-insensitive) | WORKING |
| D3 | **History → re-scan** | NavigationLink re-runs search query in ResultsView | WORKING |
| D4 | **History clear all** | Toolbar button deletes all ScanRecord rows | WORKING |
| D5 | **Saved items** | SwiftData SavedItem: product, source, saved price, link, thumbnail | WORKING |
| D6 | **Price drop indicator** | Green badge on saved row when currentLowestPrice < savedPrice | WORKING |
| D7 | **Saved → re-scan** | NavigationLink re-runs search query | WORKING |
| D8 | **Swipe to delete (Saved)** | Cascades: deletes related PriceAlert rows too | WORKING |
| D9 | **iCloud Sync** | Disabled — `AppConfig.iCloudSyncEnabled = false` (hardcoded); requires paid team | PARTIAL — toggle visible but has no effect |

---

### 1.5 Price Alerts

| # | Feature | What it does | Status |
|---|---------|-------------|--------|
| A1 | **Create alert** | From SavedView swipe action or bell button → AddAlertSheet with target price input | WORKING |
| A2 | **Permission request** | UNUserNotificationCenter permission requested at first alert creation only | WORKING |
| A3 | **Foreground check** | Checks all alerts on app foreground (scenePhase .active) and on tab appear | WORKING |
| A4 | **Manual "Check Now"** | Toolbar button re-polls all untriggered alerts immediately | WORKING |
| A5 | **Local notification** | UNNotificationRequest fires immediately when price drops below target | WORKING |
| A6 | **Triggered state** | Alert row shows green bell + "Fired!" once triggered; no re-trigger | WORKING |
| A7 | **Background polling** | Not implemented — comment in code: "Background polling is out of scope for v1" | PARTIAL — no BGTaskScheduler registration |

---

### 1.6 Authentication

| # | Feature | What it does | Status |
|---|---------|-------------|--------|
| AU1 | **Sign in with Apple** | ASAuthorizationAppleIDCredential; token + userId + displayName stored in Keychain | WORKING |
| AU2 | **Revocation check** | Cold launch checks ASAuthorizationAppleIDProvider.CredentialState; signs out if revoked | WORKING |
| AU3 | **Bearer token injection** | BackendClient.tokenProvider sends Authorization header on every request | WORKING |
| AU4 | **Token expiry** | Identity tokens expire ~10 min; no refresh mechanism (Phase 3 TODO in AuthState.swift) | PARTIAL — long sessions will fail backend auth |
| AU5 | **Sign out** | Confirmation dialog; clears Keychain; history stays on device | WORKING |
| AU6 | **Demo mode (DEBUG)** | `signInAsDemo()` — in-memory, no Keychain write, no auth header sent | WORKING (DEBUG only) |

---

### 1.7 Monetization / Quota

| # | Feature | What it does | Status |
|---|---------|-------------|--------|
| M1 | **Free scan quota** | 10 Precision scans/month in Release, 300 in DEBUG; monthly rollover by calendar month | WORKING |
| M2 | **Quota gate** | canScan() checked before photo/file/barcode precision scans; opens PaywallView on exceed | WORKING |
| M3 | **Pro (monthly)** | StoreKit 2 product `snapshop_pro_monthly`; Transaction.currentEntitlements | WORKING |
| M4 | **Pro (annual)** | StoreKit 2 product `snapshop_pro_annual` | WORKING |
| M5 | **Restore purchases** | PaywallView "Restore" button | WORKING |
| M6 | **Pro gating** | Deep scan, video upload, video file import all require isPro; photo scan quota-gated | WORKING |
| M7 | **Force Pro (DEBUG)** | Toggle in Settings debug section + 5-tap version easter egg | WORKING (DEBUG only) |
| M8 | **DEBUG paywall bypass** | "Enable Pro for Testing" button in PaywallView footer | WORKING (DEBUG only) |

---

### 1.8 Settings

| # | Feature | What it does | Status |
|---|---------|-------------|--------|
| SE1 | **Default scan mode picker** | Picker shows Precision/Deep — but stored in `@State` only; **never applied to CameraView** | BROKEN — has no effect |
| SE2 | **Retailer whitelist toggles** | 7 retailers; toggled state encoded to CSV in `@AppStorage`; correctly passed to /shop | WORKING |
| SE3 | **Haptic feedback toggle** | Toggle stored in `@State` (not @AppStorage); haptics not implemented anywhere in app | BROKEN — not persisted, not connected |
| SE4 | **Price Drop Alerts toggle** | Toggle stored in `@State` (not @AppStorage); not wired to alert check logic | BROKEN — not persisted, not connected |
| SE5 | **iCloud Sync toggle** | Toggle stored in `@State`; AppConfig.iCloudSyncEnabled always false | BROKEN — toggle has no effect |
| SE6 | **Sign out** | Confirmation dialog; working | WORKING |
| SE7 | **Privacy Policy** | NavigationLink shows `Text("Privacy Policy")` placeholder | STUB — no content |
| SE8 | **Version display** | Hardcoded "1.0.0" | WORKING |
| SE9 | **Debug section** | Force Pro toggle, quota counter, reset quota, preview paywall — DEBUG only | WORKING (DEBUG only) |

---

### 1.9 Onboarding

| # | Feature | What it does | Status |
|---|---------|-------------|--------|
| OB1 | **3-slide onboarding** | "Snap It", "Two Ways to Scan", "Your Privacy" with bullets | WORKING |
| OB2 | **Page indicator** | Animated capsule dots | WORKING |
| OB3 | **Skip button** | Visible on slides 1–2 only | WORKING |
| OB4 | **Onboarding persistence** | `@State private var hasOnboarded = false` in ContentView — **NOT @AppStorage** | BROKEN — onboarding re-shows on every cold launch restart |
| OB5 | **Auth gate** | After onboarding: SignInView shown if not signed in; Keychain-persisted | WORKING |

---

### 1.10 UI / UX Details

| # | Feature | What it does | Status |
|---|---------|-------------|--------|
| UX1 | **Dark mode** | Full theme token system (`Color.Brand.*`, `Typography.*`) throughout all views | WORKING |
| UX2 | **Reduce motion** | CameraView reads `.accessibilityReduceMotion` | WORKING |
| UX3 | **Haptic feedback** | Toggle exists in Settings but `UIFeedbackGenerator` is never called anywhere | NOT IMPLEMENTED |
| UX4 | **Dynamic Type** | `Typography.*` tokens used; some fixed sizes (e.g. `.system(size: 52)`) won't scale | PARTIAL |
| UX5 | **App logo in nav bars** | HistoryView, SettingsView toolbar show logo image | WORKING |
| UX6 | **Barcode chip** | Camera shows "barcode found" chip with value when live barcode detected | WORKING |
| UX7 | **Paste chip** | Camera shows "Paste a link" chip when URL in clipboard; hides on search focus | WORKING |
| UX8 | **Sheet → nav fix** | `onDismiss` pattern prevents SwiftUI dropping navigation push after sheet dismiss | WORKING |
| UX9 | **Symbol animations** | `.bounce` symbol effect on onboarding icon changes | WORKING |
| UX10 | **Deep scan pulse** | Recording indicator with animated ring in DEBUG overlay | WORKING |

---

## 2. TEST STATUS

**Test suite: 70 tests across 12 suites** (confirmed from source — `Snap_ShopTests.swift`)

| Suite | Tests | Description |
|-------|-------|-------------|
| ImageCropperTests | 7 | compress(), cap(), prepareForUpload() |
| KeychainStoreTests | 7 | CRUD + BackendClient token provider |
| ShippingParserTests | 10 | parseShippingCost() all cases |
| TrustLevelTests | 6 | Retailer classification |
| PoisonControlTests | 5 | Region-aware phone numbers |
| QuotaManagerTests | 6 | Quota logic + rollover (`@Suite(.serialized)`) |
| ConfidenceEscalationTests | 6 | 0.35 / 0.60 threshold boundaries |
| PriceSparklineTests | 4 | History filter + sparkline logic |
| RetailerPrefsTests | 7 | CSV encode/decode + whitelist |
| OtherItemDecodingTests | 6 | Multi-item JSON decode |
| ProStatusTests | 3 | Force-pro key + product IDs (`@Suite(.serialized)`) |
| ProductCardA11yTests | 3 | VoiceOver label composition |
| **TOTAL** | **70** | |

**Last confirmed result: 70/70 PASSED** (prior session; `@Suite(.serialized)` applied to both QuotaManagerTests and ProStatusTests to fix race condition).

> Note: Test target deployment target is iOS 26.5. Tests fail on any simulator running iOS < 26.5. Use iPhone 17 Pro simulator (id: `CADFCD85-5AA9-4623-AE58-3A387103771B`).
>
> Run command:
> ```bash
> xcodebuild test -project "Snap&Shop.xcodeproj" -scheme "Snap&Shop" \
>   -destination "platform=iOS Simulator,id=CADFCD85-5AA9-4623-AE58-3A387103771B" 2>&1 \
>   | grep -E "(Test Case|PASSED|FAILED|Executed)"
> ```

---

## 3. KNOWN ISSUES

### Code bugs

| # | Location | Issue | Impact |
|---|----------|-------|--------|
| KI1 | `ContentView.swift:5` | `@State private var hasOnboarded = false` — plain @State, not @AppStorage | Onboarding re-shows on every cold app restart |
| KI2 | `SettingsView.swift:7-9` | `iCloudSync`, `priceAlerts`, `haptics` are `@State` not `@AppStorage` | All three reset to default on every cold launch |
| KI3 | `SettingsView.swift:6` | `defaultMode` is `@State`; never read by CameraView | Default scan mode picker has zero effect |
| KI4 | `AuthState.swift:7-10` | Identity tokens expire in ~10 minutes; no refresh mechanism | Backend auth fails for long sessions without re-launch |
| KI5 | `SettingsView.swift:159-165` | Privacy Policy NavigationLink shows `Text("Privacy Policy")` placeholder | No actual policy content |
| KI6 | `AlertsView.swift:125` | Background polling explicitly deferred; comment: "out of scope for v1" | Alerts only check on app foreground or manual tap |
| KI7 | `CameraView.swift:316` | `circleButton("xmark") {}` — X button in top-bar does nothing (empty closure) | Non-functional UI element |
| KI8 | Entire codebase | `UIFeedbackGenerator` never called despite haptics toggle in Settings | Haptic feedback not implemented |

### Disabled features (hardcoded off)

| Feature | Where | Condition to enable |
|---------|-------|-------------------|
| iCloud Sync | `AppConfig.swift:10` | Set `iCloudSyncEnabled = true` + add iCloud capability + CloudKit entitlement + paid team |
| UPCitemdb fallback | `barcode.ts` | Set `UPCITEMDB_KEY` secret in Cloudflare dashboard |
| Production backend auth | `Snap_ShopApp.swift` env | Remove `DEV_AUTH_BYPASS=1` from Cloudflare Worker vars |

### Info.plist concerns

- `NSAppTransportSecurity` includes exception for `192.168.2.12` (local dev IP) — must be removed before App Store submission
- Privacy usage description strings (NSCameraUsageDescription, NSMicrophoneUsageDescription, NSPhotoLibraryUsageDescription) are **not in this plist** — verify they exist in Xcode's target Info tab; App Store will reject without them

---

## 4. SUBMISSION BLOCKERS

Items blocking capstone submission / TestFlight distribution:

| # | Blocker | Detail | Who fixes |
|---|---------|--------|-----------|
| **B1** | **No Apple Developer account in Xcode** | Xcode shows "No Accounts" error — signing cannot proceed | NEEDS-HUMAN: Xcode → Settings → Accounts → add Apple ID |
| **B2** | **No provisioning profile** | "No profiles found for com.melakunet.snapshop.demo" — device install and archive impossible | NEEDS-HUMAN: resolve after B1; use Automatic signing or create profile on developer.apple.com |
| **B3** | **Camera/Microphone/Photo privacy strings** | Info.plist does not contain NSCameraUsageDescription, NSMicrophoneUsageDescription, NSPhotoLibraryUsageDescription — App Store rejects without them; app crashes on first permission request | NEEDS-HUMAN: add in Xcode target → Info tab |
| **B4** | **Onboarding re-shows on cold launch** | `@State hasOnboarded` resets every restart; user must re-onboard and re-authenticate | AGENT-FIXABLE: change to `@AppStorage("hasOnboarded")` in ContentView |
| **B5** | **Local dev IP in ATS exception** | `192.168.2.12` HTTP exception should not ship; Apple may flag | AGENT-FIXABLE: remove that `NSExceptionDomains` entry from Info.plist |
| **B6** | **Empty entitlements file** | `Snap&Shop.entitlements` is empty (`<dict/>`); Sign in with Apple requires `com.apple.developer.applesignin` entitlement | NEEDS-HUMAN: add capability in Xcode target → Signing & Capabilities |
| **B7** | **Backend still uses DEV_AUTH_BYPASS** | Cloudflare Worker env var `DEV_AUTH_BYPASS=1` skips token validation — must be removed before real user distribution | NEEDS-HUMAN: remove from Cloudflare dashboard → Workers → snap-shop-api-dev → Settings |
| **B8** | **App Store metadata** | App name, description, screenshots, age rating, privacy policy URL all required for submission | NEEDS-HUMAN |

---

*Generated from source audit of all 30 Swift files + backend routes. No code was changed during this audit.*
