import AVFoundation
import Foundation

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
/// Auth: DEV_AUTH_BYPASS=1 is active; no token is sent.
/// TODO: attach Sign-in-with-Apple JWT before production:
///   request.setValue("Bearer \(jwt)", forHTTPHeaderField: "Authorization")
enum BackendClient {

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
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(
            "multipart/form-data; boundary=\(boundary)",
            forHTTPHeaderField: "Content-Type"
        )
        request.httpBody = buildMultipart(imageData: imageData, boundary: boundary)

        let (data, response) = try await URLSession.shared.data(for: request)
        try checkHTTP(response, data)
        return try decode(IdentifyResult.self, from: data)
    }

    /// POST JSON {"query": ..., "retailer_whitelist": []} to /shop.
    static func shop(query: String, retailerWhitelist: [String] = []) async throws -> [ShopItem] {
        let url = AppConfig.backendBaseURL.appending(path: "/shop")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(
            ShopRequestBody(query: query, retailer_whitelist: retailerWhitelist)
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
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
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
                    frames.append(jpeg)
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
        await Task.detached(priority: .utility) {
            let asset = AVURLAsset(url: url)
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: maxDimension, height: maxDimension)
            var actualTime = CMTime.zero
            guard let image = try? generator.copyCGImage(at: .zero, actualTime: &actualTime) else { return nil }
            return UIImage(cgImage: image).jpegData(compressionQuality: 0.7)
        }.value
    }

    // MARK: — Multipart helpers

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
}
