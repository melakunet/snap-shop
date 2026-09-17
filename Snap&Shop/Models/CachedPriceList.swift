import Foundation
import SwiftData

@Model
final class CachedPriceList {
    var normalizedQuery: String
    var itemsJSON: Data
    var fetchedAt: Date

    init(normalizedQuery: String, itemsJSON: Data, fetchedAt: Date) {
        self.normalizedQuery = normalizedQuery
        self.itemsJSON = itemsJSON
        self.fetchedAt = fetchedAt
    }

    /// Lowercase, trim, and collapse internal whitespace so "Nike Air Max " and
    /// "nike  air  max" map to the same cache entry.
    static func normalize(_ query: String) -> String {
        query
            .lowercased()
            .trimmingCharacters(in: .whitespaces)
            .components(separatedBy: .whitespaces)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}
