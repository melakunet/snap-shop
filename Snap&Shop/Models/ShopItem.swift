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
    let rating: Double?         // backend: rating (nil when not available)
    let reviewCount: Int?       // backend: review_count (nil when not available)
    let title: String?          // product name from retailer/SerpAPI
    let snippet: String?        // short product description from SerpAPI
    let productId: String?      // backend: product_id (Google Shopping ID, for reviews)
}
