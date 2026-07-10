import SwiftUI
import SwiftData

@main
struct Snap_ShopApp: App {

    @StateObject private var authState = AuthState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(authState)
                .onAppear {
                    // Wire the bearer token into BackendClient once, at app startup.
                    // authState is a class captured by reference; the closure always
                    // reads the current identityToken (updated on sign-in / sign-out).
                    BackendClient.tokenProvider = { [authState] in authState.identityToken }
                }
        }
        .modelContainer(for: ScanRecord.self)
    }
}
