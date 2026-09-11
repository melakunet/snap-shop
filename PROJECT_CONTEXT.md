# Snap&Shop — Project Context

## What Is This App

Snap&Shop is a product-identification and price-comparison app. The user points their camera at any physical product, the app identifies it using AI vision, then fetches live prices from 7+ major retailers. It has two scan modes, plant/hazardous item detection, voice input, price alerts, saved items, scan history, and a Pro subscription via in-app purchase.

The iOS app is production-quality and fully built. The backend is a Cloudflare Workers REST API that both iOS (current) and Android (planned) consume.

---

## Repository Layout

```
Snap-Shop/
├── Snap&Shop/                  ← Xcode project (iOS app)
│   └── Snap&Shop/
│       ├── Auth/               ← Sign in with Apple, Keychain
│       ├── Models/             ← SwiftData + Codable data types
│       ├── Network/            ← BackendClient (all API calls), AppConfig
│       ├── Scan/               ← CameraSession, SpeechTranscriber, ImageCropper
│       ├── Theme/              ← Design tokens (colors, typography, spacing)
│       └── Views/              ← All SwiftUI screens
├── backend/                    ← Cloudflare Workers (Hono, TypeScript)
│   └── src/
│       ├── middleware/         ← auth.ts (Apple JWT), ratelimit, telemetry
│       ├── routes/             ← identify-precision, identify-deep, shop, transcribe, product-reviews, identify-url
│       └── services/           ← groq, gemini, serpapi, barcode, plant-id, whisper, etc.
├── Debug.xcconfig
├── Release.xcconfig
└── PROJECT_CONTEXT.md          ← this file
```

---

## iOS App — Full Feature List

### Scanning

| Feature | Detail |
|---|---|
| **Precision Mode** | Single photo → Groq vision AI identifies product |
| **Deep Mode** | 10-second video pan → 8 keyframes → Gemini 2.5 Flash (escalates to Pro on low confidence) |
| **Barcode Detection** | Live scanner via AVCaptureMetadataOutput (EAN-13, EAN-8, UPC-E, Code128, QR) |
| **Barcode Lookup** | UPC database; ISBNs use Google Books API |
| **URL Paste** | Paste a product page link → AI extracts product identity |
| **Photo Import** | Pick from photo library |
| **Video Import** | Import video → extract 8 keyframes → deep scan |
| **Voice Input** | Live mic via SFSpeechRecognizer (on-device) |
| **Video Audio Transcription** | On-device SFSpeechURLRecognition → Groq Whisper fallback |
| **Inline Video Crop** | Saliency-aware crop overlay with rule-of-thirds grid |

### Results & Price Comparison

| Feature | Detail |
|---|---|
| **Live Prices** | SerpAPI (Google Shopping) across Amazon, Walmart, Best Buy, Target, eBay, Home Depot, B&H |
| **Retailer Whitelist** | User picks which retailers to show in Settings |
| **Trust Badges** | Major retailer vs. marketplace classification |
| **Price + Shipping Total** | Parsed delivery cost added to extracted price for true total |
| **Sort by Price / Reviews** | Toggle between cheapest and highest Bayesian-weighted rating |
| **Price Sparkline** | Historical price chart across multiple scans of the same product (P4.004) |
| **Multi-Item Chips** | Deep scan detects multiple products in one pan; chips to switch between them (P4.006) |
| **Product Reviews** | Rating breakdown bars + top review snippets (per product_id) |
| **Confidence Escalation** | Low-confidence precision result → banner prompting Deep Scan (P4.002) |
| **Low-Stock / Trust Indicators** | Shipping-total ranking + trust badges (P4.003) |

### Plant & Hazard Detection

| Feature | Detail |
|---|---|
| **Plant Detection** | Fires a specialist AI pass when Groq/Gemini flags a plant-like result |
| **Hazard Levels** | fatal / severe / moderate — displayed as colour-coded warning cards |
| **Safety Notes** | Berry/mushroom/unknown plant — extra caution copy added even for non-danger plants |
| **Suppress Shopping** | Dangerous plants get an empty search_query so no prices are fetched |
| **Poison Control Numbers** | Region-aware (CA, US, GB + generic fallback) with `tel:` links |
| **Plant Unidentified** | Honest 422 if species cannot be confirmed; never falls through to hallucinated shopping |

### Data Persistence

| Feature | Detail |
|---|---|
| **Scan History** | All scans stored in SwiftData (ScanRecord); searchable, swipe-to-delete |
| **Saved Items** | Bookmark any result (SavedItem); tracks current lowest price for price-drop detection |
| **Price Alerts** | Set a target price on any saved item (PriceAlert); triggers local notification |
| **Alert Polling** | Background check fires when app comes to foreground |
| **iCloud Sync** | Feature flag exists (disabled — requires paid Apple team + CloudKit entitlement) |

### Authentication & Monetization

| Feature | Detail |
|---|---|
| **Sign in with Apple** | Full ASAuthorization flow; identity token stored in Keychain |
| **Revocation Check** | ASAuthorizationAppleIDProvider credential state checked on every launch |
| **Free Tier** | 10 precision scans/month (DEBUG override: 300) |
| **Pro — Monthly** | Unlimited scans, Deep mode, video import, price alerts |
| **Pro — Annual** | Same features + 3-day free trial |
| **StoreKit 2** | Transaction verification via `Transaction.currentEntitlements`; revocationDate check |
| **Debug Force Pro** | Tap version label 5× in Settings → toggle Pro without purchase |

### UI / UX

- 5-tab navigation: Scan, History, Saved, Alerts, Settings
- Onboarding: 3-slide carousel gated behind `@AppStorage("hasSeenOnboarding")`
- Design tokens in `Theme/Tokens.swift`: Brand.accent, scanDeep, success, error, warning; typography scale; spacing (xs → xxxl)
- Spring animations for mode switch, pulsing deep-scan overlay, capsule page indicator
- Haptics toggle in Settings (ready but not fully wired in all paths)
- CameraView: corner-bracket viewfinder (Precision), animated pulsing overlay (Deep), flash toggle, mode toggle

---

## Backend — Full API Reference

**Runtime:** Cloudflare Workers  
**Framework:** Hono (TypeScript)  
**Auth middleware:** Apple ID JWT verified via JWKS (`https://appleid.apple.com/auth/keys`)

### Endpoints

| Method | Path | Description |
|---|---|---|
| POST | `/identify/precision` | Single image → Groq vision → optional plant specialist → IdentifyResult |
| POST | `/identify/deep` | Up to 8 frames → Gemini 2.5 Flash/Pro → optional plant specialist → IdentifyResult |
| POST | `/identify/url` | Product page URL → AI extracts identity → IdentifyResult |
| POST | `/shop` | Query + retailer whitelist + sort → [ShopItem] via SerpAPI |
| POST | `/transcribe` | Audio file → Groq Whisper → `{ transcript }` |
| GET | `/product/reviews` | `?product_id=X` → ProductReviews (rating breakdown + snippets) |

### AI Provider Chain

| Route | Primary | Escalation |
|---|---|---|
| `/identify/precision` | Groq (llava/vision) | — |
| `/identify/deep` | Gemini 2.5 Flash | Gemini 2.5 Pro (low confidence) |
| Plant specialist (both) | Dedicated Groq plant-id model | honest 422 on failure |
| `/transcribe` | Groq Whisper | iOS on-device SFSpeech (fallback done client-side) |

### Services

| File | Purpose |
|---|---|
| `groq.ts` | Vision identification; retry + backoff; confidence floor to block hallucination |
| `gemini.ts` | Deep scan multi-frame identification |
| `plant-id.ts` | Plant specialist pass; shapePlantResponse; hazard signal detection |
| `serpapi.ts` | Google Shopping fetch; retailer whitelist filter; Google-owned URL replacement |
| `barcode.ts` | UPC lookup + Google Books for ISBNs |
| `whisper.ts` | Groq Whisper audio transcription |
| `url-identify.ts` | Parse product pages by URL |
| `product-reviews.ts` | Rating breakdown + review snippets |
| `cache.ts` | KV-backed caching layer |
| `ebay.ts` | eBay-specific fetch |
| `bestbuy.ts` | Best Buy-specific fetch |

### Auth Middleware (`middleware/auth.ts`)

Currently accepts **Apple ID JWTs only** via JWKS.  
Dev bypass: `ENVIRONMENT=dev` + `DEV_AUTH_BYPASS=1` header.

---

## Data Models

### iOS (Swift / SwiftData)

```
ScanRecord       id, date, productName, mode, thumbnailData, lowestPrice, searchQuery
SavedItem        id, productName, searchQuery, thumbnailData, savedPrice, savedDate, link, source, currentLowestPrice
PriceAlert       id, savedItemId, productName, searchQuery, targetPrice, createdDate, lastCheckedDate, triggered
```

### Backend / Network (Codable ↔ JSON snake_case)

```
IdentifyResult   brand, model, category, confidence, searchQuery, imageURL?, plant?, otherItems?[]
ShopItem         price, extractedPrice, delivery, source, link, thumbnail, rating?, reviewCount?, title?, snippet?, productId?
PlantResult      commonName, latinName, confidence, featuresObserved[], hazardSignals[], warning?, safetyNote?
PlantWarning     level (fatal/severe/moderate), note
ProductReviews   rating, reviewCount, breakdown (RatingBreakdown), topReviews (ReviewItem[])
```

---

## Completed Work (Phase 4 Tickets)

| Ticket | Description | Status |
|---|---|---|
| P4.001 | ISBN barcodes via Google Books; honest 422 on lookup miss (no Groq hallucination from barcode labels) | ✅ Done |
| P4.002 | Confidence escalation — low-confidence precision result shows Deep Scan banner | ✅ Done |
| P4.003 | Shipping-total ranking + trust badges on result cards | ✅ Done |
| P4.004 | Price sparkline chart in ResultsView (price history across scans) | ✅ Done |
| P4.005 | Retailer whitelist (audio input + paste-a-link fully implemented) | ✅ Done |
| P4.006 | Multi-item Deep scan chips — detect multiple products, switchable in ResultsView | ✅ Done |
| P4.007 | Unit + UI tests expanded (35 → 70 tests) | ✅ Done |
| P4.008 | Latency gate verified live (P50 4198 ms, PASS) | ✅ Done |
| P4.009 | Groq retry + backoff; clean error messages; confidence floor to prevent hallucinated identification | ✅ Done |

---

## Android Version — Plan

### Decision
- **Framework:** Kotlin + Jetpack Compose
- **Auth:** Google Sign-In (backend needs Google JWT support added)

### What the backend already handles (no change needed)
All AI identification, price comparison, plant detection, barcode lookup, URL parsing, and transcription endpoints are platform-agnostic REST — Android consumes them identically to iOS.

### Backend change required first
`backend/src/middleware/auth.ts` — currently only verifies Apple JWTs. Need to add a Google ID token verification branch (`https://oauth2.googleapis.com/tokeninfo`) so Android users can authenticate.

### iOS → Android Component Mapping

| iOS | Android Equivalent |
|---|---|
| SwiftUI | Jetpack Compose |
| AVFoundation / CameraX | CameraX |
| AVCaptureMetadataOutput (barcode) | ML Kit Barcode Scanning |
| SFSpeechRecognizer | Android SpeechRecognizer API |
| SwiftData | Room (SQLite ORM) |
| StoreKit 2 | Google Play Billing Library 6+ |
| Sign in with Apple | Google Sign-In |
| Keychain | EncryptedSharedPreferences |
| UNUserNotificationCenter | NotificationManager + WorkManager |
| Vision saliency crop | ML Kit / manual crop |
| AVAssetExportSession (audio) | MediaExtractor |

### Android Project Structure (planned)

```
android/
├── app/src/main/
│   ├── java/com/snapshop/
│   │   ├── MainActivity.kt
│   │   ├── auth/             ← Google Sign-In, token storage
│   │   ├── camera/           ← CameraX + ML Kit barcode
│   │   ├── network/          ← Retrofit/OkHttp BackendClient
│   │   ├── data/             ← Room DB (ScanRecord, SavedItem, PriceAlert)
│   │   ├── billing/          ← Play Billing Pro subscription
│   │   ├── models/           ← Data classes mirroring iOS models
│   │   └── ui/
│   │       ├── camera/
│   │       ├── results/
│   │       ├── history/
│   │       ├── saved/
│   │       ├── alerts/
│   │       ├── settings/
│   │       ├── onboarding/
│   │       ├── paywall/
│   │       └── theme/        ← Tokens.kt (1:1 with iOS Tokens.swift)
│   └── AndroidManifest.xml
└── build.gradle.kts
```

### Android Dependency Stack

```kotlin
// UI
compose-bom, material3, navigation-compose, accompanist

// Camera & ML
camera-x (core, camera2, lifecycle, view)
mlkit-barcode-scanning

// Network
retrofit2, okhttp3, kotlinx-serialization-json

// Database
room-runtime, room-ktx

// Auth
play-services-auth (Google Sign-In)

// Billing
billing-ktx

// Background / Notifications
workmanager-ktx

// Charts (sparkline)
vico (Compose chart library)
```

### Android Build Order

1. Backend: add Google JWT auth support
2. Android project scaffold + theme tokens
3. Network layer (Retrofit hitting same backend)
4. Auth (Google Sign-In → EncryptedSharedPreferences)
5. Camera screen (CameraX, ML Kit barcode, photo/video capture)
6. Results screen (price cards, sort, trust badges, sparkline)
7. History + Saved screens (Room DB)
8. Alerts (WorkManager polling, NotificationManager)
9. Onboarding + Paywall (Play Billing)
10. Settings (retailer whitelist)
11. Voice input (SpeechRecognizer)
12. Plant detection UI
13. Deep scan (video recording, frame extraction, multi-item chips)

---

## Key Technical Notes

### iOS Patterns to Know
- All network calls are in `BackendClient.swift` as static async methods; token injected at startup via `BackendClient.tokenProvider`
- SwiftData models use `@Model` macro; external storage for thumbnailData (blob)
- QuotaManager rolls over monthly using `@AppStorage("quotaMonth")` comparison
- ProStatus uses `Transaction.currentEntitlements` async stream — check `revocationDate == nil`
- CameraSession publishes images/videos via `@Published` properties; delegates are inner classes
- SpeechTranscriber is `@MainActor` — never call audio APIs off main thread
- All JSON decoding uses `.convertFromSnakeCase` keyDecodingStrategy

### Backend Patterns to Know
- Every route returns `errorBody(code, message)` on failure — the iOS client switches on `code`
- `plant_unidentified` is a special 422 code that triggers the plant-recovery UI in ResultsView
- `no_products_found` 422 triggers the empty/retry UI
- SerpAPI returns up to 40 results before whitelist filtering; final list capped at 10
- Google-owned shopping URLs are replaced with stable retailer search URLs (see `resolveLink` in serpapi.ts)
- Groq has retry + backoff with a confidence floor — results below the floor are treated as failures
