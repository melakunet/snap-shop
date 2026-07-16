import SwiftUI

struct ContentView: View {
    @AppStorage("selectedTab") private var selectedTab: Tab = .scan
    @State private var hasOnboarded = false
    @EnvironmentObject private var authState: AuthState

    var body: some View {
        if !hasOnboarded {
            OnboardingView { hasOnboarded = true }
        } else if !authState.isSignedIn {
            SignInView()
        } else {
            RootTabView(selectedTab: $selectedTab)
                .task { await authState.checkRevocation() }
        }
    }
}

// MARK: - Tab bar

struct RootTabView: View {
    @Binding var selectedTab: Tab

    var body: some View {
        TabView(selection: $selectedTab) {
            // Each tab owns its NavigationStack so nav state is isolated per tab.
            NavigationStack {
                CameraView()
            }
            .tabItem { Label("Scan", systemImage: "camera") }
            .tag(Tab.scan)

            HistoryView()
                .tabItem { Label("History", systemImage: "clock.arrow.circlepath") }
                .tag(Tab.history)

            SavedView()
                .tabItem { Label("Saved", systemImage: "heart") }
                .tag(Tab.saved)

            AlertsView()
                .tabItem { Label("Alerts", systemImage: "bell") }
                .tag(Tab.alerts)

            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
                .tag(Tab.settings)
        }
        .tint(Color.Brand.accent)
    }
}

// MARK: - Tab enum

/// String raw value lets @AppStorage persist the selection across launches
enum Tab: String {
    case scan, history, saved, alerts, settings
}

#Preview {
    ContentView()
        .environmentObject(AuthState())
}
