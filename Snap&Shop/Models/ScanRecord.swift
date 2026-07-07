import Foundation
import SwiftData

@Model
final class ScanRecord {
    var id: UUID
    var date: Date
    var productName: String
    var mode: String          // "precision" | "deep"
    @Attribute(.externalStorage) var thumbnailData: Data?
    var lowestPrice: Double
    var searchQuery: String

    init(
        id: UUID = UUID(),
        date: Date = Date(),
        productName: String,
        mode: String,
        thumbnailData: Data?,
        lowestPrice: Double,
        searchQuery: String
    ) {
        self.id = id
        self.date = date
        self.productName = productName
        self.mode = mode
        self.thumbnailData = thumbnailData
        self.lowestPrice = lowestPrice
        self.searchQuery = searchQuery
    }
}
