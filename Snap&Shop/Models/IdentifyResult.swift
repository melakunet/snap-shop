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
    let imageURL: String?                 // backend: image_url — populated by /identify/url only
    let plant: PlantResult?               // backend: plant — present only for plant-like scans
    let otherItems: [OtherItem]?          // backend: other_items — P4.006, deep pan multi-item
}

/// One additional item detected during a Deep pan (beyond the primary best match).
/// Added additively to the deep-scan response — old clients ignore it via optional decoding.
struct OtherItem: Codable, Identifiable {
    let brand: String
    let model: String
    let category: String
    let confidence: Double
    let searchQuery: String     // backend: search_query
    let frameIndex: Int?        // backend: frame_index — which frame this was spotted in

    var id: String { searchQuery }

    var displayName: String {
        let parts = [brand, model].filter { !$0.isEmpty }
        return parts.isEmpty ? category.capitalized : parts.joined(separator: " ")
    }
}
