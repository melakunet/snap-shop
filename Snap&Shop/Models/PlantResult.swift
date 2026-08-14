import Foundation

/// Backend schema: attached to IdentifyResult when the scanned subject is plant-like.
/// Snake_case fields decoded automatically via BackendClient's .convertFromSnakeCase decoder.
struct PlantWarning: Codable {
    let level: String   // "fatal" | "severe" | "moderate"
    let note: String
}

struct PlantResult: Codable {
    let commonName: String      // backend: common_name
    let latinName: String       // backend: latin_name
    let confidence: Double
    let featuresObserved: [String]  // backend: features_observed
    let hazardSignals: [String]     // backend: hazard_signals
    let warning: PlantWarning?
    let safetyNote: String?         // backend: safety_note
}
