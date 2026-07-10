import Foundation

struct ReviewItem: Codable, Identifiable {
    let id = UUID()
    let author: String?
    let rating: Double?
    let text: String
    let date: String?

    // id is excluded from Codable — UUID is generated locally for SwiftUI identity
    enum CodingKeys: String, CodingKey {
        case author, rating, text, date
    }
}

struct RatingBreakdown: Codable {
    let five: Int
    let four: Int
    let three: Int
    let two: Int
    let one: Int

    var total: Int { five + four + three + two + one }

    var counts: [(stars: Int, count: Int)] {
        [(5, five), (4, four), (3, three), (2, two), (1, one)]
    }
}

struct ProductReviews: Codable {
    let rating: Double
    let reviewCount: Int          // backend: review_count
    let breakdown: RatingBreakdown?
    let topReviews: [ReviewItem]  // backend: top_reviews
}
