import SwiftUI

struct PriceResult: Identifiable {
    let id = UUID()
    let retailer: String
    let price: String
    let shipping: String
    let rating: String
    let isBest: Bool
    let link: String
    let thumbnail: String
}

enum ResultsPhase {
    case loading
    case loaded([PriceResult])
    case empty
    case error(String)
}

struct ResultsView: View {
    var scanMode: ScanMode
    var imageData: Data?
    @State private var phase: ResultsPhase
    @State private var identifyResult: IdentifyResult?
    @State private var isSaved = false
    @State private var fetchID = 0

    @Environment(\.openURL) private var openURL
    @Environment(\.dismiss) private var dismiss

    init(
        scanMode: ScanMode = .precision,
        imageData: Data? = nil,
        phase: ResultsPhase = .loaded(PriceResult.samples)
    ) {
        self.scanMode = scanMode
        self.imageData = imageData
        // Auto-start in loading state when real image data is provided.
        // Previews without imageData fall through to the supplied phase (defaults to samples).
        _phase = State(initialValue: imageData != nil ? .loading : phase)
    }

    var body: some View {
        ZStack {
            Color.Brand.background.ignoresSafeArea()
            content
        }
        .navigationTitle("Results")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Image("AppLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 28, height: 28)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            saveButton
        }
        .task(id: fetchID) {
            guard let data = imageData, case .loading = phase else { return }
            do {
                let (product, items) = try await BackendClient.scan(imageData: data)
                identifyResult = product
                let priceResults = mapToPriceResults(items)
                phase = priceResults.isEmpty ? .empty : .loaded(priceResults)
            } catch is CancellationError {
                // User navigated away before the response arrived — no UI update needed.
            } catch {
                phase = .error(error.localizedDescription)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .loading:
            loadingView
        case .loaded(let results):
            loadedView(results)
        case .empty:
            emptyView
        case .error(let msg):
            errorView(msg)
        }
    }

    // MARK: — ShopItem → PriceResult

    private func mapToPriceResults(_ items: [ShopItem]) -> [PriceResult] {
        guard !items.isEmpty else { return [] }
        let sorted = items.sorted { $0.extractedPrice < $1.extractedPrice }
        let bestPrice = sorted.first?.extractedPrice ?? 0
        return sorted.map { item in
            PriceResult(
                retailer: item.source,
                price: item.price,
                shipping: item.delivery,
                rating: "",
                isBest: bestPrice > 0 && item.extractedPrice == bestPrice,
                link: item.link,
                thumbnail: item.thumbnail
            )
        }
    }

    // MARK: — Loaded

    private func loadedView(_ results: [PriceResult]) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                productHeader
                    .padding(.horizontal, Spacing.xl)
                VStack(spacing: Spacing.sm) {
                    ForEach(results) { priceRow($0) }
                }
                .padding(.horizontal, Spacing.xl)
            }
            .padding(.top, Spacing.xl)
            .padding(.bottom, Spacing.xxxl)
        }
    }

    private var productHeader: some View {
        HStack(spacing: Spacing.lg) {
            capturedImageThumbnail(size: 80)
            VStack(alignment: .leading, spacing: Spacing.xs) {
                if let result = identifyResult {
                    let name = [result.brand, result.model]
                        .filter { !$0.isEmpty }
                        .joined(separator: " ")
                    Text(name.isEmpty ? result.category.capitalized : name)
                        .font(Typography.headline)
                        .foregroundStyle(Color.Brand.textPrimary)
                    Text(result.category.capitalized)
                        .font(Typography.caption)
                        .foregroundStyle(Color.Brand.textSecondary)
                } else {
                    Text("Identified Product")
                        .font(Typography.headline)
                        .foregroundStyle(Color.Brand.textPrimary)
                }
                modeBadge
            }
        }
    }

    private var modeBadge: some View {
        HStack(spacing: Spacing.xs) {
            Image(systemName: scanMode == .precision ? "camera.aperture" : "video.fill")
                .font(.system(size: 10, weight: .semibold))
            Text(scanMode == .precision ? "Precision Scan" : "Deep Scan")
                .font(Typography.caption.weight(.semibold))
        }
        .foregroundStyle(scanMode == .precision ? Color.Brand.accent : Color.Brand.scanDeep)
    }

    private func priceRow(_ result: PriceResult) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                HStack(spacing: Spacing.sm) {
                    Text(result.retailer)
                        .font(Typography.callout.weight(.semibold))
                        .foregroundStyle(Color.Brand.textPrimary)
                    if result.isBest { bestBadge }
                }
                let subtitle = result.rating.isEmpty
                    ? result.shipping
                    : "\(result.shipping) · \(result.rating)"
                Text(subtitle)
                    .font(Typography.caption)
                    .foregroundStyle(Color.Brand.textSecondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: Spacing.xs) {
                Text(result.price)
                    .font(Typography.callout.weight(.bold))
                    .foregroundStyle(result.isBest ? Color.Brand.success : Color.Brand.textPrimary)
                Button("View") {
                    if !result.link.isEmpty, let url = URL(string: result.link) {
                        openURL(url)
                    }
                }
                .font(Typography.caption.weight(.semibold))
                .foregroundStyle(Color.Brand.accent)
                .disabled(result.link.isEmpty)
            }
        }
        .padding(Spacing.lg)
        .background(Color.Brand.surface)
        .clipShape(RoundedRectangle(cornerRadius: Radius.md))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md)
                .strokeBorder(
                    result.isBest ? Color.Brand.success.opacity(0.5) : Color.Brand.border,
                    lineWidth: result.isBest ? 1.5 : 1
                )
        )
    }

    private var bestBadge: some View {
        HStack(spacing: 3) {
            Image(systemName: "checkmark")
                .font(.system(size: 9, weight: .bold))
            Text("Best Price")
                .font(Typography.caption.weight(.semibold))
        }
        .foregroundStyle(Color.white)
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, 2)
        .background(Color.Brand.success)
        .clipShape(Capsule())
    }

    // MARK: — Loading skeleton

    private var loadingView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                HStack(spacing: Spacing.lg) {
                    // Show the captured image immediately while identification runs.
                    capturedImageThumbnail(size: 80)
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        ShimmerRect(height: 18).frame(width: 180)
                        ShimmerRect(height: 14).frame(width: 90)
                    }
                    Spacer()
                }
                .padding(.horizontal, Spacing.xl)

                VStack(spacing: Spacing.sm) {
                    ForEach(0..<4, id: \.self) { _ in skeletonRow }
                }
                .padding(.horizontal, Spacing.xl)
            }
            .padding(.top, Spacing.xl)
        }
    }

    /// Captured image preview or grey placeholder at a given square size.
    private func capturedImageThumbnail(size: CGFloat) -> some View {
        Group {
            if let data = imageData, let uiImage = UIImage(data: data) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
            } else {
                Color.Brand.surfaceAlt
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: Radius.md))
    }

    private var skeletonRow: some View {
        HStack {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                ShimmerRect(height: 16).frame(width: 100)
                ShimmerRect(height: 13).frame(width: 150)
            }
            Spacer()
            ShimmerRect(height: 20).frame(width: 64)
        }
        .padding(Spacing.lg)
        .background(Color.Brand.surface)
        .clipShape(RoundedRectangle(cornerRadius: Radius.md))
    }

    // MARK: — Empty

    private var emptyView: some View {
        centeredState(
            CenteredStateConfig(
                icon: "magnifyingglass",
                iconColor: Color.Brand.textSecondary,
                title: "No results found",
                body: "We couldn't match this product.\nTry Deep Scan for a better result.",
                actionLabel: "Try Deep Scan"
            )
        ) { dismiss() }
    }

    // MARK: — Error

    private func errorView(_ message: String) -> some View {
        centeredState(
            CenteredStateConfig(
                icon: "wifi.exclamationmark",
                iconColor: Color.Brand.error,
                title: "Couldn't load prices",
                body: message,
                actionLabel: "Try Again"
            )
        ) {
            phase = .loading
            fetchID += 1
        }
    }

    // MARK: — Shared centred layout

    private func centeredState(_ config: CenteredStateConfig, action: @escaping () -> Void) -> some View {
        VStack(spacing: Spacing.xl) {
            Image(systemName: config.icon)
                .font(.system(size: 52))
                .foregroundStyle(config.iconColor)
            VStack(spacing: Spacing.sm) {
                Text(config.title)
                    .font(Typography.headline)
                    .foregroundStyle(Color.Brand.textPrimary)
                Text(config.body)
                    .font(Typography.body)
                    .foregroundStyle(Color.Brand.textSecondary)
                    .multilineTextAlignment(.center)
            }
            Button(config.actionLabel, action: action)
                .font(Typography.callout.weight(.semibold))
                .foregroundStyle(Color.Brand.accentOn)
                .padding(.horizontal, Spacing.xxl)
                .padding(.vertical, Spacing.md)
                .background(Color.Brand.accent)
                .clipShape(RoundedRectangle(cornerRadius: Radius.md))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(Spacing.xxl)
    }

    // MARK: — Toolbar

    private var saveButton: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                withAnimation(.spring(duration: 0.25)) { isSaved.toggle() }
            } label: {
                Image(systemName: isSaved ? "bookmark.fill" : "bookmark")
                    .foregroundStyle(Color.Brand.accent)
                    .symbolEffect(.bounce, value: isSaved)
            }
        }
    }
}

// MARK: — Config type (replaces 6-param centeredState)

private struct CenteredStateConfig {
    let icon: String
    let iconColor: Color
    let title: String
    let body: String
    let actionLabel: String
}

// MARK: — Shimmer helper

private struct ShimmerRect: View {
    @State private var isShimmering = false
    var height: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: Radius.sm)
            .fill(Color.Brand.surfaceAlt)
            .frame(height: height)
            .opacity(isShimmering ? 0.4 : 0.9)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.85).repeatForever(autoreverses: true)) {
                    isShimmering = true
                }
            }
    }
}

// MARK: — Sample data (previews only)

extension PriceResult {
    static let samples: [PriceResult] = [
        PriceResult(retailer: "Amazon",   price: "$279.99", shipping: "Free",   rating: "4.8★", isBest: true,  link: "", thumbnail: ""),
        PriceResult(retailer: "Walmart",  price: "$289.95", shipping: "$5.99",  rating: "4.6★", isBest: false, link: "", thumbnail: ""),
        PriceResult(retailer: "Best Buy", price: "$299.99", shipping: "Free",   rating: "4.7★", isBest: false, link: "", thumbnail: ""),
        PriceResult(retailer: "eBay",     price: "$259.00", shipping: "$12.00", rating: "4.4★", isBest: false, link: "", thumbnail: ""),
        PriceResult(retailer: "Target",   price: "$319.99", shipping: "Free",   rating: "4.5★", isBest: false, link: "", thumbnail: ""),
    ]
}

#Preview("Loaded — Precision") { NavigationStack { ResultsView() } }
#Preview("Loaded — Deep")      { NavigationStack { ResultsView(scanMode: .deep) } }
#Preview("Loading")            { NavigationStack { ResultsView(phase: .loading) } }
#Preview("Empty")              { NavigationStack { ResultsView(phase: .empty) } }
#Preview("Error")              { NavigationStack { ResultsView(phase: .error("Network connection lost. Check your Wi-Fi.")) } }
