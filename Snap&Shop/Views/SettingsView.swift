import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var authState: AuthState
    @State private var defaultMode: ScanMode = .precision
    @State private var iCloudSync = true
    @State private var priceAlerts = true
    @State private var haptics = true
    @State private var selectedRetailers: Set<String> = Set(Retailer.all.map(\.name))
    @State private var showSignOutConfirm = false

    var body: some View {
        NavigationStack {
            List {
                scanSection
                retailerSection
                notificationsSection
                privacySection
                accountSection
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.large)
            .background(Color.Brand.background.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Image("AppLogo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 28, height: 28)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
            }
            .confirmationDialog("Sign out?", isPresented: $showSignOutConfirm, titleVisibility: .visible) {
                Button("Sign Out", role: .destructive) { authState.signOut() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Your scan history will remain on this device.")
            }
        }
    }

    // MARK: — Sections

    private var scanSection: some View {
        Section {
            Picker("Default Scan Mode", selection: $defaultMode) {
                Text("Precision").tag(ScanMode.precision)
                Text("Deep").tag(ScanMode.deep)
            }
            .tint(Color.Brand.accent)

            HStack(spacing: Spacing.sm) {
                Circle()
                    .fill(defaultMode == .precision ? Color.Brand.accent : Color.Brand.scanDeep)
                    .frame(width: 8, height: 8)
                Text(defaultMode == .precision ? "Single high-accuracy photo" : "Video pan & multi-image burst")
                    .font(Typography.caption)
                    .foregroundStyle(Color.Brand.textSecondary)
            }
            .animation(.easeInOut(duration: 0.2), value: defaultMode)
        } header: {
            sectionHeader("Scanning")
        }
        .listRowBackground(Color.Brand.surface)
        .listRowSeparatorTint(Color.Brand.border)
    }

    private var retailerSection: some View {
        Section {
            ForEach(Retailer.all) { retailer in
                Toggle(isOn: Binding(
                    get: { selectedRetailers.contains(retailer.name) },
                    set: { on in
                        if on {
                            selectedRetailers.insert(retailer.name)
                        } else {
                            selectedRetailers.remove(retailer.name)
                        }
                    }
                )) {
                    HStack(spacing: Spacing.md) {
                        Image(systemName: retailer.icon)
                            .frame(width: 28)
                            .foregroundStyle(Color.Brand.accent)
                        Text(retailer.name)
                            .font(Typography.body)
                            .foregroundStyle(Color.Brand.textPrimary)
                    }
                }
                .tint(Color.Brand.accent)
            }
        } header: {
            sectionHeader("Trusted Retailers")
        }
        .listRowBackground(Color.Brand.surface)
        .listRowSeparatorTint(Color.Brand.border)
    }

    private var notificationsSection: some View {
        Section {
            Toggle("Price Drop Alerts", isOn: $priceAlerts)
                .font(Typography.body)
                .foregroundStyle(Color.Brand.textPrimary)
                .tint(Color.Brand.accent)
            Toggle("Haptic Feedback", isOn: $haptics)
                .font(Typography.body)
                .foregroundStyle(Color.Brand.textPrimary)
                .tint(Color.Brand.accent)
        } header: {
            sectionHeader("Notifications & Feedback")
        }
        .listRowBackground(Color.Brand.surface)
        .listRowSeparatorTint(Color.Brand.border)
    }

    private var privacySection: some View {
        Section {
            Toggle("iCloud Sync", isOn: $iCloudSync)
                .font(Typography.body)
                .foregroundStyle(Color.Brand.textPrimary)
                .tint(Color.Brand.accent)
            NavigationLink {
                Text("Privacy Policy")
                    .font(Typography.body)
                    .foregroundStyle(Color.Brand.textPrimary)
                    .padding()
            } label: {
                Text("Privacy Policy")
                    .font(Typography.body)
                    .foregroundStyle(Color.Brand.textPrimary)
            }
        } header: {
            sectionHeader("Privacy & Data")
        }
        .listRowBackground(Color.Brand.surface)
        .listRowSeparatorTint(Color.Brand.border)
    }

    private var accountSection: some View {
        Section {
            // Signed-in identity row
            HStack(spacing: Spacing.md) {
                Image(systemName: "person.circle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(Color.Brand.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text(authState.displayName ?? "Apple User")
                        .font(Typography.body)
                        .foregroundStyle(Color.Brand.textPrimary)
                    Text("Signed in with Apple")
                        .font(Typography.caption)
                        .foregroundStyle(Color.Brand.textSecondary)
                }
                Spacer()
            }
            .padding(.vertical, Spacing.xs)

            Button { showSignOutConfirm = true } label: {
                Text("Sign Out")
                    .font(Typography.body)
                    .foregroundStyle(Color.Brand.error)
            }
            HStack {
                Text("Version")
                    .font(Typography.body)
                    .foregroundStyle(Color.Brand.textPrimary)
                Spacer()
                Text("1.0.0")
                    .font(Typography.body)
                    .foregroundStyle(Color.Brand.textSecondary)
            }
        } header: {
            sectionHeader("Account")
        }
        .listRowBackground(Color.Brand.surface)
        .listRowSeparatorTint(Color.Brand.border)
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(Typography.caption.weight(.semibold))
            .foregroundStyle(Color.Brand.textSecondary)
            .textCase(nil)
    }
}

private struct Retailer: Identifiable {
    let id = UUID()
    let name: String
    let icon: String

    static let all: [Retailer] = [
        Retailer(name: "Amazon", icon: "cart.fill"),
        Retailer(name: "Walmart", icon: "bag.fill"),
        Retailer(name: "Best Buy", icon: "tv.fill"),
        Retailer(name: "eBay", icon: "tag.fill"),
        Retailer(name: "Target", icon: "scope"),
        Retailer(name: "B&H", icon: "camera.fill")
    ]
}

#Preview {
    SettingsView()
}
