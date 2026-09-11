# Snap & Shop

[![CI](https://github.com/melakunet/Snap-Shop/actions/workflows/ci.yml/badge.svg)](https://github.com/melakunet/Snap-Shop/actions/workflows/ci.yml)

> AI-powered shopping assistant iOS app — scan products, barcodes, or video to instantly find prices across retailers. Built with SwiftUI, Cloudflare Workers, Gemini 2.5, and Groq vision.

Capstone project — triOS College, 2026

---

## What It Does

Point your camera at any product and Snap & Shop identifies it and shows you the best prices from retailers like Amazon, eBay, and Best Buy — in seconds.

| Scan Mode | How It Works |
|-----------|-------------|
| **Photo** | Apple Vision OCR reads on-device text, Groq vision identifies the product |
| **Barcode** | AVFoundation detects EAN-13, UPC, and ISBN barcodes fully on-device — no AI required |
| **Video (Deep Scan)** | Gemini 2.5 analyses multiple frames for complex or hard-to-identify items |
| **Paste a Link** | Resolves the product URL and fetches live comparison prices instantly |

---

## Features

- **Multi-modal scanning** — photo, barcode, video, and URL
- **On-device processing** — barcodes and OCR run locally via AVFoundation and Apple Vision; no data sent for those steps
- **Real-time price comparison** — Best Buy, eBay, Amazon, and more via Google Shopping
- **Plant identification** — species detection with safety warnings for dangerous plants
- **Book lookup** — ISBN barcodes resolved via Google Books and Open Library
- **Scan history** — every result saved locally with thumbnail
- **Price alerts** — get notified when a saved item drops in price
- **Pro tier** — unlimited scans via StoreKit 2 in-app purchase
- **Sign in with Apple** — private, secure authentication
- **Dark mode** — full support with accessible color contrast and Dynamic Type

---

## Tech Stack

**iOS (On-Device)**
- Swift / SwiftUI (iOS 18+)
- AVFoundation — camera, barcode scanning, video recording
- Apple Vision — on-device OCR for text extraction
- StoreKit 2 — in-app purchases
- Sign in with Apple

**Backend** *(Cloudflare Workers — Cloud AI)*
- [Gemini 2.5 Flash / Pro](https://deepmind.google/technologies/gemini/) — deep video identification
- [Groq](https://groq.com/) — fast vision inference for photo scans
- [SerpAPI](https://serpapi.com/) — Google Shopping results
- Best Buy API + eBay API — direct retailer pricing
- Google Books + Open Library — ISBN lookups

---

## Architecture

```
iOS App (SwiftUI)
    │
    ├── CameraView        — AVFoundation capture: photo / video / barcode
    ├── ImageCropper      — Apple Vision OCR (on-device text recognition)
    ├── ResultsView       — price cards, product info, plant warnings
    ├── BackendClient     — URLSession calls to Cloudflare Worker
    │
    └── Backend (Workers)
            ├── /identify/precision   — Groq vision + barcode + plant specialist
            ├── /identify/deep        — Gemini 2.5 multi-frame analysis
            ├── /shop                 — Best Buy + eBay + SerpAPI price aggregation
            └── /transcribe           — Whisper audio hint for deep scans
```

---

## Getting Started

### Prerequisites
- Xcode 16+
- iOS 18 device or simulator
- Node.js 20+ (for backend)
- [Wrangler CLI](https://developers.cloudflare.com/workers/wrangler/) (`npm i -g wrangler`)

### Backend
```bash
cd backend
npm install
npx wrangler dev        # local dev
npx wrangler deploy     # deploy to Cloudflare
```

Set these secrets in the Cloudflare dashboard:
```
GEMINI_API_KEY
GROQ_API_KEY
SERPAPI_KEY
```

### iOS App
1. Open `Snap&Shop.xcodeproj` in Xcode
2. Set your Team in Signing & Capabilities
3. Update `AppConfig.swift` with your Worker URL
4. Press `Cmd+R` to build and run

---

## Project Structure

```
Snap&Shop/
├── Auth/           — Sign in with Apple, Keychain
├── Models/         — ShopItem, IdentifyResult, ScanRecord, etc.
├── Network/        — BackendClient, AppConfig
├── Scan/           — CameraSession, ImageCropper, SpeechTranscriber
├── Views/          — CameraView, ResultsView, PaywallView, SettingsView, …
└── Theme/          — Design tokens, colors, typography

backend/
├── src/routes/     — identify-precision, identify-deep, shop, transcribe
└── src/services/   — gemini, groq, serpapi, barcode, plant-id, bestbuy, ebay
```

---

## License

Academic project — triOS College, 2026. Not licensed for commercial use.
