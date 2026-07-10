import SwiftData
import SwiftUI

private enum ReviewsPhase {
    case idle
    case loading
    case loaded(ProductReviews)
    case failed(String)
}

struct ProductDetailView: View {
    let result: PriceResult
    let sortMode: SortMode

    @Environment(\.openURL) private var openURL
    @State private var reviewsPhase: ReviewsPhase = .idle

    private let goldColor = Color(red: 1, green: 0.76, blue: 0)

    var body: some View {
        ZStack {
            Color.Brand.background.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    heroImage
                    infoSection
                        .padding(.horizontal, Spacing.xl)
                        .padding(.top, Spacing.xl)
                    if let snippet = result.snippet {
                        aboutSection(snippet)
                            .padding(.horizontal, Spacing.xl)
                            .padding(.top, Spacing.xl)
                    }
                    if case .loaded(let reviews) = reviewsPhase {
                        reviewsSection(reviews)
                            .padding(.horizontal, Spacing.xl)
                            .padding(.top, Spacing.xl)
                    }
                    actionButtons
                        .padding(.horizontal, Spacing.xl)
                        .padding(.top, Spacing.xl)
                        .padding(.bottom, Spacing.xxxl)
                }
            }
        }
        .navigationTitle(result.retailer)
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: — Hero

    private var heroImage: some View {
        Group {
            if let url = URL(string: result.thumbnail), !result.thumbnail.isEmpty {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    default:
                        heroPlaceholder
                    }
                }
            } else {
                heroPlaceholder
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 240)
        .clipped()
    }

    private var heroPlaceholder: some View {
        ZStack {
            Color.Brand.surfaceAlt
            Image(systemName: "photo")
                .font(.system(size: 48))
                .foregroundStyle(Color.Brand.textSecondary.opacity(0.4))
        }
    }

    // MARK: — Info

    private var infoSection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text(result.title ?? result.retailer)
                .font(Typography.headline)
                .foregroundStyle(Color.Brand.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: Spacing.sm) {
                retailerBadge
                if result.isBest { bestBadge }
            }

            if result.rating != nil || !result.shipping.isEmpty {
                metaRow
            }

            priceRow
        }
    }

    private var retailerBadge: some View {
        HStack(spacing: Spacing.xs) {
            Image(systemName: "storefront")
                .font(.system(size: 11, weight: .semibold))
            Text(result.retailer)
                .font(Typography.caption.weight(.semibold))
        }
        .foregroundStyle(Color.Brand.accent)
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, Spacing.xs)
        .background(Color.Brand.accent.opacity(0.12))
        .clipShape(Capsule())
    }

    private var bestBadge: some View {
        HStack(spacing: 3) {
            Image(systemName: sortMode == .reviews ? "star.fill" : "checkmark")
                .font(.system(size: 9, weight: .bold))
            Text(sortMode == .reviews ? "Top Rated" : "Best Price")
                .font(Typography.caption.weight(.semibold))
        }
        .foregroundStyle(Color.white)
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, Spacing.xs)
        .background(Color.Brand.success)
        .clipShape(Capsule())
    }

    private var metaRow: some View {
        HStack(spacing: Spacing.lg) {
            if let r = result.rating {
                HStack(spacing: Spacing.xs) {
                    starRow(rating: r, size: 13)
                    Text(String(format: "%.1f", r))
                        .font(Typography.callout.weight(.semibold))
                        .foregroundStyle(Color.Brand.textPrimary)
                    if let count = result.reviewCount {
                        Text("(\(count.formatted()))")
                            .font(Typography.caption)
                            .foregroundStyle(Color.Brand.textSecondary)
                    }
                }
            }
            if !result.shipping.isEmpty {
                HStack(spacing: Spacing.xs) {
                    Image(systemName: "shippingbox")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.Brand.textSecondary)
                    Text(result.shipping)
                        .font(Typography.caption)
                        .foregroundStyle(Color.Brand.textSecondary)
                }
            }
        }
    }

    private var priceRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.xs) {
            Text(result.price)
                .font(.system(size: 32, weight: .bold, design: .default))
                .foregroundStyle(result.isBest ? Color.Brand.success : Color.Brand.textPrimary)
            Spacer()
        }
    }

    private func starRow(rating: Double, size: CGFloat) -> some View {
        HStack(spacing: 2) {
            ForEach(1...5, id: \.self) { i in
                let filled = Double(i) <= rating
                let half = !filled && Double(i) - 0.5 <= rating
                Image(systemName: filled ? "star.fill" : (half ? "star.leadinghalf.filled" : "star"))
                    .font(.system(size: size))
                    .foregroundStyle(goldColor)
            }
        }
    }

    // MARK: — About

    private func aboutSection(_ snippet: String) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("About this product")
                .font(Typography.callout.weight(.semibold))
                .foregroundStyle(Color.Brand.textPrimary)
            Text(snippet)
                .font(Typography.body)
                .foregroundStyle(Color.Brand.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Spacing.lg)
        .background(Color.Brand.surface)
        .clipShape(RoundedRectangle(cornerRadius: Radius.md))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md)
                .strokeBorder(Color.Brand.border, lineWidth: 1)
        )
    }

    // MARK: — Reviews

    private func reviewsSection(_ reviews: ProductReviews) -> some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            reviewsHeader(reviews)
            if let bd = reviews.breakdown {
                breakdownBars(bd)
            }
            if !reviews.topReviews.isEmpty {
                Divider().overlay(Color.Brand.border)
                ForEach(Array(reviews.topReviews.enumerated()), id: \.offset) { _, review in
                    reviewCard(review)
                    if review.id != reviews.topReviews.last?.id {
                        Divider().overlay(Color.Brand.border)
                    }
                }
            }
        }
        .padding(Spacing.lg)
        .background(Color.Brand.surface)
        .clipShape(RoundedRectangle(cornerRadius: Radius.md))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md)
                .strokeBorder(Color.Brand.border, lineWidth: 1)
        )
    }

    private func reviewsHeader(_ reviews: ProductReviews) -> some View {
        HStack(spacing: Spacing.sm) {
            starRow(rating: reviews.rating, size: 15)
            Text(String(format: "%.1f", reviews.rating))
                .font(Typography.callout.weight(.bold))
                .foregroundStyle(Color.Brand.textPrimary)
            Text("· \(reviews.reviewCount.formatted()) reviews")
                .font(Typography.caption)
                .foregroundStyle(Color.Brand.textSecondary)
        }
    }

    private func breakdownBars(_ bd: RatingBreakdown) -> some View {
        let maxCount = bd.counts.map(\.count).max() ?? 1
        return VStack(spacing: Spacing.xs) {
            ForEach(bd.counts, id: \.stars) { stars, count in
                HStack(spacing: Spacing.sm) {
                    Text("\(stars)★")
                        .font(Typography.caption)
                        .foregroundStyle(Color.Brand.textSecondary)
                        .frame(width: 28, alignment: .trailing)
                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.Brand.surfaceAlt)
                            RoundedRectangle(cornerRadius: 3)
                                .fill(goldColor)
                                .frame(width: proxy.size.width * CGFloat(count) / CGFloat(maxCount))
                        }
                    }
                    .frame(height: 8)
                    let pct = bd.total > 0 ? Int(Double(count) / Double(bd.total) * 100) : 0
                    Text("\(pct)%")
                        .font(Typography.caption)
                        .foregroundStyle(Color.Brand.textSecondary)
                        .frame(width: 36, alignment: .trailing)
                }
            }
        }
    }

    private func reviewCard(_ review: ReviewItem) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack {
                if let author = review.author {
                    Text(author)
                        .font(Typography.caption.weight(.semibold))
                        .foregroundStyle(Color.Brand.textPrimary)
                }
                Spacer()
                HStack(spacing: Spacing.sm) {
                    if let r = review.rating {
                        starRow(rating: r, size: 10)
                    }
                    if let date = review.date {
                        Text(date)
                            .font(Typography.caption)
                            .foregroundStyle(Color.Brand.textSecondary)
                    }
                }
            }
            Text(review.text)
                .font(Typography.caption)
                .foregroundStyle(Color.Brand.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: — Actions

    private var actionButtons: some View {
        VStack(spacing: Spacing.sm) {
            Button {
                guard !result.link.isEmpty, let url = URL(string: result.link) else { return }
                openURL(url)
            } label: {
                Label("Open at \(result.retailer)", systemImage: "safari")
                    .font(Typography.callout.weight(.semibold))
                    .foregroundStyle(Color.Brand.accentOn)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Spacing.md)
                    .background(Color.Brand.accent)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md))
            }
            .disabled(result.link.isEmpty)

            reviewsControl
        }
    }

    @ViewBuilder
    private var reviewsControl: some View {
        switch reviewsPhase {
        case .idle:
            Button { loadReviews() } label: {
                Label("See reviews", systemImage: "text.bubble")
                    .font(Typography.callout.weight(.semibold))
                    .foregroundStyle(result.productId != nil ? Color.Brand.accent : Color.Brand.textSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Spacing.md)
                    .background(Color.Brand.accent.opacity(result.productId != nil ? 0.1 : 0.05))
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md))
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.md)
                            .strokeBorder(
                                result.productId != nil
                                    ? Color.Brand.accent.opacity(0.3)
                                    : Color.Brand.border,
                                lineWidth: 1
                            )
                    )
            }

        case .loading:
            HStack(spacing: Spacing.sm) {
                ProgressView()
                    .tint(Color.Brand.accent)
                Text("Loading reviews…")
                    .font(Typography.callout)
                    .foregroundStyle(Color.Brand.textSecondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Spacing.md)
            .background(Color.Brand.surface)
            .clipShape(RoundedRectangle(cornerRadius: Radius.md))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.md)
                    .strokeBorder(Color.Brand.border, lineWidth: 1)
            )

        case .loaded:
            // Reviews shown inline above — button collapses to a hide affordance
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { reviewsPhase = .idle }
            } label: {
                Label("Hide reviews", systemImage: "chevron.up")
                    .font(Typography.caption.weight(.semibold))
                    .foregroundStyle(Color.Brand.textSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Spacing.sm)
            }

        case .failed(let msg):
            VStack(alignment: .leading, spacing: Spacing.xs) {
                HStack(spacing: Spacing.xs) {
                    Image(systemName: "exclamationmark.circle")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.Brand.error)
                    Text(msg)
                        .font(Typography.caption)
                        .foregroundStyle(Color.Brand.textSecondary)
                }
                Button("Try again") { loadReviews() }
                    .font(Typography.caption.weight(.semibold))
                    .foregroundStyle(Color.Brand.accent)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Spacing.md)
            .background(Color.Brand.surface)
            .clipShape(RoundedRectangle(cornerRadius: Radius.md))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.md)
                    .strokeBorder(Color.Brand.border, lineWidth: 1)
            )
        }
    }

    private func loadReviews() {
        guard let productId = result.productId else {
            reviewsPhase = .failed("Reviews are not available for items from \(result.retailer).")
            return
        }
        reviewsPhase = .loading
        Task {
            do {
                let reviews = try await BackendClient.productReviews(productId: productId)
                withAnimation(.easeInOut(duration: 0.25)) {
                    reviewsPhase = .loaded(reviews)
                }
            } catch is CancellationError {
                // view dismissed, no update needed
            } catch {
                reviewsPhase = .failed(error.localizedDescription)
            }
        }
    }
}

// MARK: — Previews

#Preview("Idle") {
    NavigationStack {
        ProductDetailView(result: PriceResult.samples[0], sortMode: .price)
    }
    .modelContainer(for: ScanRecord.self, inMemory: true)
}

#Preview("No product_id") {
    NavigationStack {
        ProductDetailView(result: PriceResult.samples[3], sortMode: .price)
    }
    .modelContainer(for: ScanRecord.self, inMemory: true)
}

#Preview("Top Rated") {
    NavigationStack {
        ProductDetailView(result: PriceResult.samples[2], sortMode: .reviews)
    }
    .modelContainer(for: ScanRecord.self, inMemory: true)
}
