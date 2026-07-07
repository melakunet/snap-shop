import SwiftUI
import SwiftData

@main
struct Snap_ShopApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(for: ScanRecord.self)
    }
}
