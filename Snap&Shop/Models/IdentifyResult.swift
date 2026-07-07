import Foundation

/// Backend schema: POST /identify/precision → IdentifyResult
/// Snake_case fields decoded automatically via BackendClient's .convertFromSnakeCase decoder.
struct IdentifyResult: Codable {
    let brand: String
    let model: String
    let category: String
    let distinguishingFeatures: [String]  // backend: distinguishing_features
    let confidence: Double
    let searchQuery: String               // backend: search_query
}
