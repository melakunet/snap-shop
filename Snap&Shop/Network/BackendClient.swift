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

/// Stateless network client for the Snap&Shop backend.
/// All methods are static and nonisolated — safe to call from any actor context.
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

    // MARK: — Public API

    /// POST multipart/form-data to /identify/precision.
    /// Form field name "image" matches what the backend's formData.get('image') expects.
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

    /// Full scan: identify image, then fetch prices using the returned search_query.
    static func scan(imageData: Data) async throws -> (IdentifyResult, [ShopItem]) {
        let product = try await identifyPrecision(imageData: imageData)
        let prices = try await shop(query: product.searchQuery)
        return (product, prices)
    }

    // MARK: — Helpers

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
