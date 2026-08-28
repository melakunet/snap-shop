import SwiftUI
import SwiftData
import UserNotifications

struct AlertsView: View {
    @Query(sort: \PriceAlert.createdDate, order: .reverse) private var alerts: [PriceAlert]
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @State private var isChecking = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color.Brand.background.ignoresSafeArea()
                if alerts.isEmpty {
                    emptyState
                } else {
                    alertList
                }
            }
            .navigationTitle("Alerts")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                if !alerts.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            Task { await checkAllAlerts() }
                        } label: {
                            if isChecking {
                                ProgressView().tint(Color.Brand.accent)
                            } else {
                                Text("Check Now")
                                    .foregroundStyle(Color.Brand.accent)
                            }
                        }
                        .disabled(isChecking)
                    }
                }
            }
        }
        .task { await checkAllAlerts() }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active { Task { await checkAllAlerts() } }
        }
    }

    private var emptyState: some View {
        VStack(spacing: Spacing.lg) {
            Spacer()
            Image(systemName: "bell.slash")
                .font(.system(size: 52))
                .foregroundStyle(Color.Brand.textSecondary)
            Text("No Price Alerts")
                .font(Typography.headline)
                .foregroundStyle(Color.Brand.textPrimary)
            Text("Tap the bell icon on a saved item to set a price-drop target.")
                .font(Typography.body)
                .foregroundStyle(Color.Brand.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Spacing.xl)
            Spacer()
        }
    }

    private var alertList: some View {
        List {
            ForEach(alerts) { alert in
                alertRow(alert)
                    .listRowBackground(Color.Brand.surface)
                    .listRowSeparatorTint(Color.Brand.border)
            }
            .onDelete { indexSet in
                for index in indexSet { modelContext.delete(alerts[index]) }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
    }

    private func alertRow(_ alert: PriceAlert) -> some View {
        HStack(spacing: Spacing.md) {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(alert.productName)
                    .font(Typography.callout.weight(.semibold))
                    .foregroundStyle(Color.Brand.textPrimary)
                    .lineLimit(2)

                HStack(spacing: Spacing.xs) {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.system(size: 11))
                    Text("Alert below \(alert.targetPrice.formatted(.currency(code: "USD")))")
                        .font(Typography.caption)
                }
                .foregroundStyle(Color.Brand.accent)

                if let checked = alert.lastCheckedDate {
                    Text("Checked \(checked.formatted(.relative(presentation: .named)))")
                        .font(Typography.caption)
                        .foregroundStyle(Color.Brand.textSecondary)
                }
            }

            Spacer()

            if alert.triggered {
                VStack(alignment: .trailing, spacing: 2) {
                    Image(systemName: "bell.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(Color.Brand.success)
                        .accessibilityHidden(true)
                    Text("Fired!")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Color.Brand.success)
                }
            } else {
                Image(systemName: "bell")
                    .font(.system(size: 20))
                    .foregroundStyle(Color.Brand.textSecondary.opacity(0.5))
                    .accessibilityHidden(true)
            }
        }
        .padding(.vertical, Spacing.xs)
    }

    // Background polling is out of scope for v1 — this check runs on foreground and manual trigger only.
    private func checkAllAlerts() async {
        guard !isChecking else { return }
        isChecking = true
        defer { isChecking = false }

        for alert in alerts {
            guard !alert.triggered else { continue }
            guard let shopItems = try? await BackendClient.shop(query: alert.searchQuery, sort: "price"),
                  let lowest = shopItems.min(by: { $0.extractedPrice < $1.extractedPrice }),
                  lowest.extractedPrice > 0
            else { continue }

            alert.lastCheckedDate = Date()

            let savedId = alert.savedItemId
            let descriptor = FetchDescriptor<SavedItem>(predicate: #Predicate { $0.id == savedId })
            if let saved = try? modelContext.fetch(descriptor).first {
                saved.currentLowestPrice = lowest.extractedPrice
            }

            if lowest.extractedPrice <= alert.targetPrice {
                alert.triggered = true
                scheduleNotification(for: alert, price: lowest.extractedPrice)
            }
        }
    }

    private func scheduleNotification(for alert: PriceAlert, price: Double) {
        let content = UNMutableNotificationContent()
        content.title = "Price Drop!"
        content.body = "\(alert.productName) is now \(price.formatted(.currency(code: "USD"))) — below your \(alert.targetPrice.formatted(.currency(code: "USD"))) target."
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: alert.id.uuidString,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }
}

// MARK: — Add Alert Sheet

struct AddAlertSheet: View {
    let item: SavedItem
    @State private var targetText = ""
    @State private var isSaving = false
    @State private var errorMessage: String? = nil
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    private var targetPrice: Double? {
        Double(
            targetText
                .replacingOccurrences(of: "$", with: "")
                .trimmingCharacters(in: .whitespaces)
        )
    }

    private var isValid: Bool { (targetPrice ?? 0) > 0 }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.Brand.background.ignoresSafeArea()
                VStack(spacing: Spacing.xl) {
                    VStack(spacing: Spacing.sm) {
                        Image(systemName: "bell.badge")
                            .font(.system(size: 44))
                            .foregroundStyle(Color.Brand.accent)
                        Text("Alert me below…")
                            .font(Typography.headline)
                            .foregroundStyle(Color.Brand.textPrimary)
                        Text(item.productName)
                            .font(Typography.body)
                            .foregroundStyle(Color.Brand.textSecondary)
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                    }

                    HStack(spacing: Spacing.sm) {
                        Text("$")
                            .font(Typography.title)
                            .foregroundStyle(Color.Brand.textSecondary)
                        TextField("0.00", text: $targetText)
                            .font(Typography.title)
                            .foregroundStyle(Color.Brand.textPrimary)
                            .keyboardType(.decimalPad)
                            .tint(Color.Brand.accent)
                    }
                    .padding(Spacing.lg)
                    .background(Color.Brand.surface)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md))

                    Text("Currently saved at \(item.savedPrice.formatted(.currency(code: "USD")))")
                        .font(Typography.caption)
                        .foregroundStyle(Color.Brand.textSecondary)

                    if let error = errorMessage {
                        Text(error)
                            .font(Typography.caption)
                            .foregroundStyle(Color.Brand.error)
                            .multilineTextAlignment(.center)
                    }

                    Button { Task { await save() } } label: {
                        ZStack {
                            Text("Set Alert").opacity(isSaving ? 0 : 1)
                            if isSaving { ProgressView().tint(Color.Brand.accentOn) }
                        }
                        .font(Typography.callout.weight(.semibold))
                        .foregroundStyle(Color.Brand.accentOn)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(isValid ? Color.Brand.accent : Color.Brand.accent.opacity(0.4))
                        .clipShape(RoundedRectangle(cornerRadius: Radius.md))
                    }
                    .disabled(!isValid || isSaving)

                    Spacer()
                }
                .padding(Spacing.xl)
            }
            .navigationTitle("Price Alert")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Color.Brand.textSecondary)
                }
            }
        }
    }

    private func save() async {
        guard let price = targetPrice, price > 0 else { return }
        isSaving = true

        // Request permission at first alert creation — never at app launch.
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        if settings.authorizationStatus == .notDetermined {
            _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
        }

        let alert = PriceAlert(
            savedItemId: item.id,
            productName: item.productName,
            searchQuery: item.searchQuery,
            targetPrice: price
        )
        modelContext.insert(alert)
        try? modelContext.save()
        isSaving = false
        dismiss()
    }
}

#Preview {
    AlertsView()
        .modelContainer(
            try! ModelContainer(
                for: Schema([ScanRecord.self, SavedItem.self, PriceAlert.self]),
                configurations: ModelConfiguration(isStoredInMemoryOnly: true)
            )
        )
}
