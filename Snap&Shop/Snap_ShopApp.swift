import SwiftUI
import SwiftData

@main
struct Snap_ShopApp: App {
    @StateObject private var authState = AuthState()
    @StateObject private var proStatus = ProStatus()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(authState)
                .environmentObject(proStatus)
                .onAppear {
                    BackendClient.tokenProvider = { [authState] in authState.identityToken }
                }
                .task { await proStatus.refresh() }
        }
        .modelContainer(appModelContainer)
    }
}

private let appModelContainer: ModelContainer = {
    let schema = Schema([ScanRecord.self, SavedItem.self, PriceAlert.self])
    let config: ModelConfiguration
    if AppConfig.iCloudSyncEnabled {
        // Prerequisites before enabling: iCloud capability in the target, CloudKit entitlement,
        // and a private iCloud container ID configured in the entitlements file.
        // These require a paid Apple Developer account — not added here.
        config = ModelConfiguration(schema: schema, cloudKitDatabase: .automatic)
    } else {
        config = ModelConfiguration(schema: schema)
    }
    return try! ModelContainer(for: schema, configurations: config)
}()
