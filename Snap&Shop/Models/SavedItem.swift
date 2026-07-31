import Foundation
import SwiftData

@Model
final class SavedItem {
    var id: UUID
    var productName: String
    var searchQuery: String
    @Attribute(.externalStorage) var thumbnailData: Data?
    var savedPrice: Double
    var savedDate: Date
    var link: String
    var source: String
    var currentLowestPrice: Double?

    init(
        productName: String,
        searchQuery: String,
        thumbnailData: Data?,
        savedPrice: Double,
        link: String,
        source: String
    ) {
        self.id = UUID()
        self.productName = productName
        self.searchQuery = searchQuery
        self.thumbnailData = thumbnailData
        self.savedPrice = savedPrice
        self.savedDate = Date()
        self.link = link
        self.source = source
        self.currentLowestPrice = nil
    }
}
