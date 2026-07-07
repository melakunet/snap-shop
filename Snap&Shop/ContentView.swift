import SwiftUI

struct ContentView: View {
    /// Persisted across launches so the user returns to where they left off
    @AppStorage("selectedTab") private var selectedTab: Tab = .scan
    /// Set to true by OnboardingFlow once the user taps "Get started"
    @AppStorage("hasOnboarded") private var hasOnboarded = false

    var body: some View {
        if hasOnboarded {
            RootTabView(selectedTab: $selectedTab)
        } else {
            OnboardingView {
                hasOnboarded = true
            }
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
}
