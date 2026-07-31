import Foundation
import SwiftData

@Model
final class PriceAlert {
    var id: UUID
    var savedItemId: UUID
    var productName: String
    var searchQuery: String
    var targetPrice: Double
    var createdDate: Date
    var lastCheckedDate: Date?
    var triggered: Bool

    init(savedItemId: UUID, productName: String, searchQuery: String, targetPrice: Double) {
        self.id = UUID()
        self.savedItemId = savedItemId
        self.productName = productName
        self.searchQuery = searchQuery
        self.targetPrice = targetPrice
        self.createdDate = Date()
        self.lastCheckedDate = nil
        self.triggered = false
    }
}
