import AVFoundation
import Foundation
import UIKit

enum BackendError: Error, LocalizedError {
    case httpError(Int, String)
    case decodingError(Error)

    var errorDescription: String? {
        switch self {
        case .httpError(let code, let body): "HTTP \(code): \(body)"
        case .decodingError(let err): "Decode error: \(err.localizedDescription)"
        }
    }
}

enum DeepScanError: Error, LocalizedError {
    case zeroDuration
    case noFrames

    var errorDescription: String? {
        switch self {
        case .zeroDuration: "The video has no duration."
        case .noFrames: "Could not extract frames from the video."
        }
    }
}

/// Stateless network client for the Snap&Shop backend.
/// All methods are static — safe to call from any actor context.
///
/// Auth: set `tokenProvider` once at app startup (see Snap_ShopApp.swift).
/// Every request built via `makeRequest` automatically carries the bearer token.
/// When DEV_AUTH_BYPASS=1 is active on the backend, a missing/invalid token is
/// silently ignored — remove that flag to enforce real Apple JWT validation locally.
enum BackendClient {

    // MARK: — Auth

    /// Injected at app startup; returns the current Apple identity token or nil (signed out).
    /// Reading it on every request means sign-out takes effect immediately without
    /// restarting any in-flight sessions.
    static var tokenProvider: (() -> String?)? = nil

    /// Builds a URLRequest pre-loaded with the HTTP method and, when signed in,
    /// the Authorization: Bearer header. All public methods use this instead of
    /// constructing URLRequest directly.
    private static func makeRequest(url: URL, method: String = "GET") -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        if let token = tokenProvider?() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        return request
    }

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()

    // MARK: — Precision

    /// POST multipart/form-data to /identify/precision.
    static func identifyPrecision(imageData: Data) async throws -> IdentifyResult {
        let url = AppConfig.backendBaseURL.appending(path: "/identify/precision")
        let boundary = UUID().uuidString
        var request = makeRequest(url: url, method: "POST")
        request.setValue(
            "multipart/form-data; boundary=\(boundary)",
            forHTTPHeaderField: "Content-Type"
        )
        request.httpBody = buildMultipart(imageData: imageData, boundary: boundary)

        let (data, response) = try await URLSession.shared.data(for: request)
        try checkHTTP(response, data)
        return try decode(IdentifyResult.self, from: data)
    }

    /// POST JSON {"query": ..., "retailer_whitelist": [], "sort": "price"|"reviews"} to /shop.
    static func shop(query: String, retailerWhitelist: [String] = [], sort: String = "price") async throws -> [ShopItem] {
        let url = AppConfig.backendBaseURL.appending(path: "/shop")
        var request = makeRequest(url: url, method: "POST")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(
            ShopRequestBody(query: query, retailer_whitelist: retailerWhitelist, sort: sort)
        )

        let (data, response) = try await URLSession.shared.data(for: request)
        try checkHTTP(response, data)
        return try decode([ShopItem].self, from: data)
    }

    /// Full precision scan: identify image then fetch prices.
    static func scan(imageData: Data) async throws -> (IdentifyResult, [ShopItem]) {
        let product = try await identifyPrecision(imageData: imageData)
        let prices = try await shop(query: product.searchQuery)
        return (product, prices)
    }

    // MARK: — Deep

    /// POST multipart/form-data to /identify/deep.
    /// Field name "frames[]" matches backend's formData.getAll('frames[]').
    static func identifyDeep(frames: [Data], hint: String? = nil) async throws -> IdentifyResult {
        let url = AppConfig.backendBaseURL.appending(path: "/identify/deep")
        let boundary = UUID().uuidString
        var request = makeRequest(url: url, method: "POST")
        request.setValue(
            "multipart/form-data; boundary=\(boundary)",
            forHTTPHeaderField: "Content-Type"
        )
        request.httpBody = buildDeepMultipart(frames: frames, hint: hint, boundary: boundary)

        let (data, response) = try await URLSession.shared.data(for: request)
        try checkHTTP(response, data)
        return try decode(IdentifyResult.self, from: data)
    }

    /// Full deep scan: extract keyframes, identify, fetch prices.
    static func scanDeep(videoURL: URL, hint: String? = nil) async throws -> (IdentifyResult, [ShopItem]) {
        let frames = try await extractKeyframes(from: videoURL, count: 8)
        let product = try await identifyDeep(frames: frames, hint: hint)
        let prices = try await shop(query: product.searchQuery)
        return (product, prices)
    }

    /// Extract up to `count` evenly-spaced JPEG keyframes from a video file.
    static func extractKeyframes(from url: URL, count: Int = 8) async throws -> [Data] {
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration)
        let durationSeconds = CMTimeGetSeconds(duration)
        guard durationSeconds > 0 else { throw DeepScanError.zeroDuration }

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 512, height: 512)
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = CMTime(seconds: 1, preferredTimescale: 600)

        let step = durationSeconds / Double(count)
        let requestTimes = (0..<count).map { i -> NSValue in
            NSValue(time: CMTime(seconds: step * Double(i) + step / 2, preferredTimescale: 600))
        }

        return try await withCheckedThrowingContinuation { continuation in
            var frames: [Data] = []
            let total = requestTimes.count
            var processed = 0

            generator.generateCGImagesAsynchronously(forTimes: requestTimes) { _, image, _, result, _ in
                if result == .succeeded, let cgImage = image,
                   let jpeg = UIImage(cgImage: cgImage).jpegData(compressionQuality: 0.7) {
                    let capped = ImageCropper.cap(jpeg: jpeg)
                    #if DEBUG
                    if capped.count != jpeg.count {
                        print("[ImageCropper] keyframe capped: \(jpeg.count / 1_024) KB → \(capped.count / 1_024) KB")
                    }
                    #endif
                    frames.append(capped)
                }
                processed += 1
                if processed == total {
                    frames.isEmpty
                        ? continuation.resume(throwing: DeepScanError.noFrames)
                        : continuation.resume(returning: frames)
                }
            }
        }
    }

    /// Extract a single JPEG thumbnail from the first frame of a video (for history records).
    static func extractThumbnail(from url: URL, maxDimension: CGFloat = 120) async -> Data? {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: maxDimension, height: maxDimension)
        guard let (cgImage, _) = try? await generator.image(at: .zero) else { return nil }
        return UIImage(cgImage: cgImage).jpegData(compressionQuality: 0.7)
    }

    // MARK: — URL identify

    /// POST { url } to /identify/url, then fetch prices for the resolved search query.
    static func identifyURL(url: URL) async throws -> (IdentifyResult, [ShopItem]) {
        let endpoint = AppConfig.backendBaseURL.appending(path: "/identify/url")
        var request = makeRequest(url: endpoint, method: "POST")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(URLIdentifyBody(url: url.absoluteString))

        let (data, response) = try await URLSession.shared.data(for: request)
        try checkHTTP(response, data)
        let product = try decode(IdentifyResult.self, from: data)
        let prices = try await shop(query: product.searchQuery)
        return (product, prices)
    }

    // MARK: — Reviews

    /// GET /product/reviews?product_id=... — fetches rating breakdown + top review snippets.
    static func productReviews(productId: String) async throws -> ProductReviews {
        var components = URLComponents(
            url: AppConfig.backendBaseURL.appending(path: "/product/reviews"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [URLQueryItem(name: "product_id", value: productId)]
        guard let url = components.url else {
            throw BackendError.httpError(0, "Could not build reviews URL")
        }
        let request = makeRequest(url: url, method: "GET")

        let (data, response) = try await URLSession.shared.data(for: request)
        try checkHTTP(response, data)
        return try decode(ProductReviews.self, from: data)
    }

    // MARK: — Transcribe

    /// Extract audio from a video URL, upload to /transcribe, and return the transcript.
    /// Falls back to empty string rather than throwing so a missing transcript never blocks scan.
    static func transcribeAudio(videoURL: URL) async throws -> String {
        let audioURL = try await extractAudioFromVideo(videoURL)
        defer { try? FileManager.default.removeItem(at: audioURL) }

        let audioData = try Data(contentsOf: audioURL)
        let url = AppConfig.backendBaseURL.appending(path: "/transcribe")
        let boundary = UUID().uuidString
        var request = makeRequest(url: url, method: "POST")
        request.setValue(
            "multipart/form-data; boundary=\(boundary)",
            forHTTPHeaderField: "Content-Type"
        )
        request.httpBody = buildAudioMultipart(
            audioData: audioData,
            filename: audioURL.lastPathComponent,
            boundary: boundary
        )

        let (data, response) = try await URLSession.shared.data(for: request)
        try checkHTTP(response, data)
        let decoded = try decode(TranscribeResponse.self, from: data)
        return decoded.transcript
    }

    // MARK: — Multipart helpers

    private static func extractAudioFromVideo(_ videoURL: URL) async throws -> URL {
        let asset = AVURLAsset(url: videoURL)
        let outputURL = FileManager.default.temporaryDirectory
            .appending(path: "\(UUID().uuidString).m4a")

        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            throw BackendError.httpError(0, "Could not create AVAssetExportSession")
        }
        session.outputURL = outputURL
        session.outputFileType = .m4a

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            session.exportAsynchronously {
                switch session.status {
                case .completed:
                    continuation.resume()
                default:
                    continuation.resume(throwing: BackendError.httpError(
                        0,
                        session.error?.localizedDescription ?? "Audio export failed"
                    ))
                }
            }
        }
        return outputURL
    }

    private static func buildAudioMultipart(audioData: Data, filename: String, boundary: String) -> Data {
        var body = Data()
        func append(_ string: String) {
            if let d = string.data(using: .utf8) { body.append(d) }
        }
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"audio\"; filename=\"\(filename)\"\r\n")
        append("Content-Type: audio/m4a\r\n\r\n")
        body.append(audioData)
        append("\r\n--\(boundary)--\r\n")
        return body
    }

    private static func buildMultipart(imageData: Data, boundary: String) -> Data {
        var body = Data()
        func append(_ string: String) {
            if let d = string.data(using: .utf8) { body.append(d) }
        }
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"image\"; filename=\"scan.jpg\"\r\n")
        append("Content-Type: image/jpeg\r\n\r\n")
        body.append(imageData)
        append("\r\n--\(boundary)--\r\n")
        return body
    }

    private static func buildDeepMultipart(frames: [Data], hint: String?, boundary: String) -> Data {
        var body = Data()
        func append(_ string: String) {
            if let d = string.data(using: .utf8) { body.append(d) }
        }
        for (i, frame) in frames.enumerated() {
            append("--\(boundary)\r\n")
            append("Content-Disposition: form-data; name=\"frames[]\"; filename=\"frame_\(i).jpg\"\r\n")
            append("Content-Type: image/jpeg\r\n\r\n")
            body.append(frame)
            append("\r\n")
        }
        if let hint, !hint.isEmpty {
            append("--\(boundary)\r\n")
            append("Content-Disposition: form-data; name=\"hint\"\r\n\r\n")
            append(hint)
            append("\r\n")
        }
        append("--\(boundary)--\r\n")
        return body
    }

    // MARK: — Shared helpers

    private static func checkHTTP(_ response: URLResponse, _ data: Data) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard (200..<300).contains(http.statusCode) else {
            let preview = String(data: data, encoding: .utf8).map { String($0.prefix(300)) } ?? ""
            throw BackendError.httpError(http.statusCode, preview)
        }
    }

    private static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try decoder.decode(type, from: data)
        } catch {
            throw BackendError.decodingError(error)
        }
    }
}

// MARK: — Private request body

private struct ShopRequestBody: Encodable {
    let query: String
    let retailer_whitelist: [String]
    let sort: String
}

private struct TranscribeResponse: Decodable {
    let transcript: String
}

private struct URLIdentifyBody: Encodable {
    let url: String
}
