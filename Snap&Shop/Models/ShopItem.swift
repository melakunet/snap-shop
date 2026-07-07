import Foundation

/// Backend schema: POST /shop → [ShopItem]
/// Snake_case fields decoded automatically via BackendClient's .convertFromSnakeCase decoder.
struct ShopItem: Codable {
    let price: String
    let extractedPrice: Double  // backend: extracted_price
    let delivery: String
    let source: String
    let link: String
    let thumbnail: String
}
