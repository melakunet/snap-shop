import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var authState: AuthState
    @EnvironmentObject private var proStatus: ProStatus
    @State private var defaultMode: ScanMode = .precision
    @State private var iCloudSync = true
    @State private var priceAlerts = true
    @State private var haptics = true
    @AppStorage(RetailerPrefs.userDefaultsKey) private var retailerSelectionCSV = ""
    @State private var showSignOutConfirm = false
    #if DEBUG
    @State private var quotaUsed = QuotaManager.scansUsed()
    @AppStorage("debug_force_pro") private var debugForcePro = false
    @State private var versionTapCount = 0
    @State private var showForceProAlert = false
    @State private var showPaywallPreview = false
    #endif

    var body: some View {
        NavigationStack {
            List {
                scanSection
                retailerSection
                notificationsSection
                privacySection
                accountSection
                #if DEBUG
                debugSection
                #endif
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
            #if DEBUG
            .fullScreenCover(isPresented: $showPaywallPreview) {
                PaywallView()
                    .environmentObject(proStatus)
            }
            #endif
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
            ForEach(RetailerPrefs.all, id: \.name) { retailer in
                Toggle(isOn: Binding(
                    get: {
                        RetailerPrefs.enabledRetailers(from: retailerSelectionCSV).contains(retailer.name)
                    },
                    set: { on in
                        var enabled = RetailerPrefs.enabledRetailers(from: retailerSelectionCSV)
                        if on { enabled.insert(retailer.name) } else { enabled.remove(retailer.name) }
                        retailerSelectionCSV = RetailerPrefs.csv(from: enabled)
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
            if !retailerSelectionCSV.isEmpty {
                Button {
                    retailerSelectionCSV = ""   // empty = all enabled = no filter
                } label: {
                    Text("Reset to All Retailers")
                        .font(Typography.body)
                        .foregroundStyle(Color.Brand.accent)
                }
            }
        } header: {
            HStack {
                sectionHeader("Trusted Retailers")
                Spacer()
                let count = RetailerPrefs.enabledRetailers(from: retailerSelectionCSV).count
                if count < RetailerPrefs.allNames.count {
                    Text("\(count) of \(RetailerPrefs.allNames.count)")
                        .font(Typography.caption)
                        .foregroundStyle(Color.Brand.textSecondary)
                }
            }
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
            #if DEBUG
            .contentShape(Rectangle())
            .onTapGesture {
                versionTapCount += 1
                if versionTapCount >= 5 {
                    versionTapCount = 0
                    debugForcePro.toggle()
                    Task { await proStatus.refresh() }
                    showForceProAlert = true
                }
            }
            #endif
        } header: {
            sectionHeader("Account")
        }
        #if DEBUG
        .alert(debugForcePro ? "Pro Override: ON" : "Pro Override: OFF",
               isPresented: $showForceProAlert) {
            Button("OK") {}
        } message: {
            Text(debugForcePro
                 ? "App now behaves as Pro. Tap version 5× again to disable."
                 : "Pro override removed. StoreKit consulted normally.")
        }
        #endif
        .listRowBackground(Color.Brand.surface)
        .listRowSeparatorTint(Color.Brand.border)
    }

    #if DEBUG
    private var debugSection: some View {
        Section {
            HStack {
                Text("Force Pro")
                    .font(Typography.body)
                    .foregroundStyle(Color.Brand.textPrimary)
                Spacer()
                Text(debugForcePro ? "ON" : "OFF")
                    .font(Typography.body.weight(.semibold))
                    .foregroundStyle(debugForcePro ? Color.Brand.success : Color.Brand.textSecondary)
            }
            HStack {
                Text("Precision Scans Used")
                    .font(Typography.body)
                    .foregroundStyle(Color.Brand.textPrimary)
                Spacer()
                Text("\(quotaUsed) / \(QuotaManager.freeLimit)")
                    .font(Typography.body)
                    .foregroundStyle(Color.Brand.textSecondary)
            }
            Button {
                QuotaManager.resetForDebug()
                quotaUsed = QuotaManager.scansUsed()
            } label: {
                Text("Reset Quota")
                    .font(Typography.body)
                    .foregroundStyle(Color.Brand.error)
            }
            Button {
                showPaywallPreview = true
            } label: {
                Text("Preview Paywall")
                    .font(Typography.body)
                    .foregroundStyle(Color.Brand.accent)
            }
        } header: {
            sectionHeader("DEBUG")
        }
        .listRowBackground(Color.Brand.surface)
        .listRowSeparatorTint(Color.Brand.border)
    }
    #endif

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(Typography.caption.weight(.semibold))
            .foregroundStyle(Color.Brand.textSecondary)
            .textCase(nil)
    }
}


#Preview {
    SettingsView()
        .environmentObject(AuthState())
        .environmentObject(ProStatus())
}
