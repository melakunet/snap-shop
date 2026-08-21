import StoreKit
import SwiftUI

struct PaywallView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var proStatus: ProStatus
    @State private var products: [Product] = []
    @State private var selectedID = ProStatus.annualID
    @State private var isPurchasing = false
    @State private var isRestoring = false
    @State private var isLoading = true
    @State private var storeUnavailable = false
    @State private var errorMessage: String? = nil

    private var selectedProduct: Product? {
        products.first { $0.id == selectedID }
    }

    var body: some View {
        ZStack {
            Color.Brand.background.ignoresSafeArea()

            if isLoading {
                ProgressView()
                    .tint(Color.Brand.accent)
            } else {
                ScrollView {
                    VStack(spacing: Spacing.xxl) {
                        header
                        featureList
                        planPicker
                        ctaButton
                        footer
                    }
                    .padding(.horizontal, Spacing.xl)
                    .padding(.top, Spacing.xxxl)
                    .padding(.bottom, Spacing.xxl)
                }
            }

            HStack {
                Image("AppLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 28, height: 28)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.Brand.textSecondary)
                        .frame(width: 30, height: 30)
                        .background(Color.Brand.surfaceAlt)
                        .clipShape(Circle())
                }
            }
            .padding([.top, .horizontal], Spacing.xl)
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .task { await loadProducts() }
    }

    // MARK: — Header

    private var header: some View {
        VStack(spacing: Spacing.md) {
            ZStack {
                Circle()
                    .fill(RadialGradient(
                        colors: [Color.Brand.accent.opacity(0.2), .clear],
                        center: .center, startRadius: 0, endRadius: 80
                    ))
                    .frame(width: 160, height: 160)
                Image(systemName: "sparkles")
                    .font(.system(size: 46))
                    .foregroundStyle(Color.Brand.accent)
            }
            Text("Snap & Shop Pro")
                .font(Typography.display)
                .foregroundStyle(Color.Brand.textPrimary)
                .multilineTextAlignment(.center)
            Text("Unlimited scans. Live prices.\nAlways the best deal.")
                .font(Typography.body)
                .foregroundStyle(Color.Brand.textSecondary)
                .multilineTextAlignment(.center)
        }
    }

    // MARK: — Features

    private var featureList: some View {
        VStack(spacing: Spacing.sm) {
            ForEach(PaywallFeature.all) { feature in
                HStack(spacing: Spacing.md) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.Brand.accent)
                        .font(.system(size: 20))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(feature.title)
                            .font(Typography.callout.weight(.semibold))
                            .foregroundStyle(Color.Brand.textPrimary)
                        Text(feature.subtitle)
                            .font(Typography.caption)
                            .foregroundStyle(Color.Brand.textSecondary)
                    }
                    Spacer()
                }
                .padding(Spacing.md)
                .background(Color.Brand.surface)
                .clipShape(RoundedRectangle(cornerRadius: Radius.md))
            }
        }
    }

    // MARK: — Plan picker

    private var planPicker: some View {
        VStack(spacing: Spacing.sm) {
            if storeUnavailable {
                storeUnavailableRow
                if let diag = errorMessage {
                    Text(diag)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Color.Brand.error)
                        .multilineTextAlignment(.leading)
                        .padding(Spacing.md)
                        .background(Color.Brand.surface)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.sm))
                }
            } else {
                ForEach(products, id: \.id) { product in
                    planCard(product)
                }
            }
        }
    }

    private var storeUnavailableRow: some View {
        VStack(spacing: Spacing.md) {
            Text("Store unavailable — check your connection and try again")
                .font(Typography.callout)
                .foregroundStyle(Color.Brand.textSecondary)
                .multilineTextAlignment(.center)
            Button {
                Task { await loadProducts() }
            } label: {
                HStack(spacing: Spacing.sm) {
                    if isLoading {
                        ProgressView()
                            .scaleEffect(0.8)
                            .tint(Color.Brand.accent)
                    }
                    Text(isLoading ? "Retrying…" : "Retry")
                        .font(Typography.callout.weight(.semibold))
                        .foregroundStyle(Color.Brand.accent)
                }
            }
            .disabled(isLoading)
        }
        .frame(maxWidth: .infinity)
        .padding(Spacing.xl)
        .background(Color.Brand.surface)
        .clipShape(RoundedRectangle(cornerRadius: Radius.md))
    }

    private func planCard(_ product: Product) -> some View {
        let selected = selectedID == product.id
        let isAnnual = product.id == ProStatus.annualID
        return Button {
            withAnimation(.spring(duration: 0.2)) { selectedID = product.id }
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: Spacing.sm) {
                        Text(product.displayName)
                            .font(Typography.callout.weight(.semibold))
                            .foregroundStyle(Color.Brand.textPrimary)
                        if isAnnual {
                            Text("BEST VALUE")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(Color.Brand.accentOn)
                                .padding(.horizontal, Spacing.sm)
                                .padding(.vertical, 2)
                                .background(Color.Brand.accent)
                                .clipShape(Capsule())
                        }
                    }
                    Text(isAnnual ? "Includes 3-day free trial" : "Billed monthly, cancel anytime")
                        .font(Typography.caption)
                        .foregroundStyle(Color.Brand.textSecondary)
                }
                Spacer()
                Text(product.displayPrice)
                    .font(Typography.headline)
                    .foregroundStyle(selected ? Color.Brand.accent : Color.Brand.textPrimary)
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selected ? Color.Brand.accent : Color.Brand.border)
                    .font(.system(size: 22))
            }
            .padding(Spacing.lg)
            .background(Color.Brand.surface)
            .clipShape(RoundedRectangle(cornerRadius: Radius.md))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.md)
                    .strokeBorder(
                        selected ? Color.Brand.accent : Color.Brand.border,
                        lineWidth: selected ? 2 : 1
                    )
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: — CTA

    private var ctaButton: some View {
        let busy = isPurchasing || isLoading
        let unavail = storeUnavailable && !isLoading
        return VStack(spacing: Spacing.sm) {
            Button {
                Task { await purchase() }
            } label: {
                ZStack {
                    if busy && !unavail {
                        ProgressView().tint(Color.Brand.accentOn)
                    } else {
                        Text(unavail
                             ? "Store Unavailable"
                             : (selectedID == ProStatus.annualID ? "Start Free Trial" : "Subscribe Now"))
                    }
                }
                .font(Typography.callout.weight(.semibold))
                .foregroundStyle(unavail ? Color.Brand.textSecondary : Color.Brand.accentOn)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(
                    unavail
                        ? Color.Brand.surfaceAlt
                        : Color.Brand.accent.opacity(busy ? 0.7 : 1.0)
                )
                .clipShape(RoundedRectangle(cornerRadius: Radius.md))
                .opacity(unavail ? 0.5 : 1.0)
            }
            .disabled(busy || selectedProduct == nil)
            .animation(.easeInOut(duration: 0.15), value: busy)
            .animation(.easeInOut(duration: 0.15), value: unavail)

            // Only show purchase/restore errors here; load diagnostics appear in planPicker above
            if let error = errorMessage, !storeUnavailable {
                Text(error)
                    .font(Typography.caption)
                    .foregroundStyle(Color.Brand.error)
                    .multilineTextAlignment(.center)
            }
        }
    }

    // MARK: — Footer

    private var footer: some View {
        VStack(spacing: Spacing.sm) {
            Button("Restore Purchases") {
                Task { await restore() }
            }
            .font(Typography.caption)
            .foregroundStyle(isRestoring ? Color.Brand.textSecondary.opacity(0.5) : Color.Brand.textSecondary)
            .disabled(isRestoring)

            Text("Cancel anytime. Billed via App Store.\nFree trial applies to annual plan only.")
                .font(Typography.caption)
                .foregroundStyle(Color.Brand.textSecondary)
                .multilineTextAlignment(.center)
        }
    }

    // MARK: — StoreKit actions

    private func loadProducts() async {
        isLoading = true
        storeUnavailable = false
        errorMessage = nil
        let requestedIDs = [ProStatus.monthlyID, ProStatus.annualID]
        let bundleID = Bundle.main.bundleIdentifier ?? "nil"
        do {
            let loaded = try await Product.products(for: requestedIDs)
            if loaded.isEmpty {
                storeUnavailable = true
                errorMessage = """
                    RESULT: 0 products returned (no error thrown)
                    REQUESTED: \(requestedIDs)
                    RETURNED: \(loaded.map(\.id))
                    BUNDLE: \(bundleID)
                    """
            } else {
                // Annual first in the list
                products = loaded.sorted { $0.id == ProStatus.annualID && $1.id != ProStatus.annualID }
            }
        } catch {
            storeUnavailable = true
            let raw = String(describing: error)
            errorMessage = """
                RESULT: threw error
                REQUESTED: \(requestedIDs)
                ERROR: \(error.localizedDescription)
                RAW: \(raw)
                BUNDLE: \(bundleID)
                """
        }
        isLoading = false
    }

    private func purchase() async {
        guard let product = selectedProduct else {
            errorMessage = "Pricing unavailable — tap Retry above to reload."
            return
        }
        isPurchasing = true
        errorMessage = nil
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                switch verification {
                case .verified(_):
                    await proStatus.refresh()
                    if proStatus.isPro { dismiss() }
                case .unverified(_, let error):
                    errorMessage = "Purchase could not be verified: \(error.localizedDescription)"
                }
            case .userCancelled:
                break
            case .pending:
                errorMessage = "Purchase is pending approval."
            @unknown default:
                break
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        isPurchasing = false
    }

    private func restore() async {
        isRestoring = true
        errorMessage = nil
        do {
            try await AppStore.sync()
            await proStatus.refresh()
            if proStatus.isPro { dismiss() }
        } catch {
            errorMessage = "Restore failed: \(error.localizedDescription)"
        }
        isRestoring = false
    }
}

// MARK: — Supporting types

private struct PaywallFeature: Identifiable {
    let id = UUID()
    let title: String
    let subtitle: String

    static let all: [PaywallFeature] = [
        PaywallFeature(title: "Unlimited Scans",       subtitle: "Scan as many products as you like"),
        PaywallFeature(title: "Deep / Video Scan",     subtitle: "Multi-image burst & video pan support"),
        PaywallFeature(title: "Live Price Tracking",   subtitle: "Real-time results from 6+ retailers"),
        PaywallFeature(title: "Price Drop Alerts",     subtitle: "Get notified when a saved item drops"),
        PaywallFeature(title: "iCloud Sync",           subtitle: "History & favourites across all your devices")
    ]
}

#Preview {
    PaywallView()
        .environmentObject(ProStatus())
}
