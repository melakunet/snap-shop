import Combine
import StoreKit
import SwiftUI

/// Tracks the user's Pro subscription status by consulting StoreKit's
/// currentEntitlements. Call refresh() at app launch and after any purchase.
@MainActor
final class ProStatus: ObservableObject {
    static let monthlyID = "snapshop_pro_monthly"
    static let annualID  = "snapshop_pro_annual"

    @Published private(set) var isPro = false

    func refresh() async {
        var hasPro = false
        for await result in Transaction.currentEntitlements {
            guard case .verified(let tx) = result,
                  tx.productType == .autoRenewable,
                  [Self.monthlyID, Self.annualID].contains(tx.productID),
                  tx.revocationDate == nil
            else { continue }
            hasPro = true
            break
        }
        isPro = hasPro
    }
}
