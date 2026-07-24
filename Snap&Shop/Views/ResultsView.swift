import AVKit
import SwiftUI
import SwiftData

struct PriceResult: Identifiable {
    let id = UUID()
    let retailer: String
    let price: String
    let shipping: String
    let isBest: Bool
    let link: String
    let thumbnail: String
    let rating: Double?
    let reviewCount: Int?
    let title: String?
    let snippet: String?
    let productId: String?
}

enum SortMode: String, CaseIterable {
    case price = "price"
    case reviews = "reviews"

    var label: String {
        switch self {
        case .price: "Best price"
        case .reviews: "Best reviewed"
        }
    }
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
    var videoURL: URL?
    var textQuery: String?
    var hint: String?
    var productPageURL: URL?
    var uploadData: Data?           // pre-cropped payload from CropSheet; skips prepareForUpload
    @Binding var prefillQuery: String
    @State private var phase: ResultsPhase
    @State private var videoPlayer: AVPlayer?
    @State private var identifyResult: IdentifyResult?
    @State private var isSaved = false
    @State private var fetchID = 0
    @State private var sortMode: SortMode = .price
    @State private var isPlaying = true
    @State private var playerCurrentTime: Double = 0
    @State private var playerDuration: Double = 1
    @State private var timeObserverToken: Any? = nil
    @State private var pausedFrameData: Data? = nil
    @State private var pausedVideoSize: CGSize = .zero   // cgImage dims from captureFrame; used by overlay
    @State private var frameImageData: Data? = nil
    @State private var showFrameResults = false
    @State private var frameScanUploadData: Data? = nil
    #if DEBUG
    @State private var debugCropPreview: UIImage? = nil
    #endif

    @Environment(\.openURL) private var openURL
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    init(
        scanMode: ScanMode = .precision,
        imageData: Data? = nil,
        videoURL: URL? = nil,
        textQuery: String? = nil,
        hint: String? = nil,
        productPageURL: URL? = nil,
        uploadData: Data? = nil,
        prefillQuery: Binding<String> = .constant(""),
        phase: ResultsPhase = .loaded(PriceResult.samples)
    ) {
        self.scanMode = scanMode
        self.imageData = imageData
        self.videoURL = videoURL
        self.textQuery = textQuery
        self.hint = hint
        self.productPageURL = productPageURL
        self.uploadData = uploadData
        _prefillQuery = prefillQuery
        let autoStart = imageData != nil || videoURL != nil || textQuery != nil || productPageURL != nil
        _phase = State(initialValue: autoStart ? .loading : phase)
        _videoPlayer = State(initialValue: videoURL.map { AVPlayer(url: $0) })
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
            guard case .loading = phase else { return }
            do {
                var shopItems: [ShopItem] = []
                var productResult: IdentifyResult? = nil
                let sort = sortMode.rawValue

                // If identify already ran (re-sort): skip identify, just re-fetch /shop
                if let result = identifyResult {
                    shopItems = try await BackendClient.shop(query: result.searchQuery, sort: sort)
                } else if let query = textQuery {
                    shopItems = try await BackendClient.shop(query: query, sort: sort)
                } else if let data = imageData {
                    let toUpload: Data
                    if let preComputed = uploadData {
                        toUpload = preComputed
                    } else {
                        toUpload = await ImageCropper.prepareForUpload(data: data)
                    }
                    let (product, items) = try await BackendClient.scan(imageData: toUpload)
                    productResult = product
                    shopItems = items
                } else if let url = videoURL {
                    let (product, items) = try await BackendClient.scanDeep(videoURL: url, hint: hint)
                    productResult = product
                    shopItems = items
                } else if let pageURL = productPageURL {
                    let (product, items) = try await BackendClient.identifyURL(url: pageURL)
                    productResult = product
                    shopItems = items
                } else {
                    return
                }

                if let product = productResult {
                    identifyResult = product
                }

                let priceResults = mapToPriceResults(shopItems)
                if priceResults.isEmpty {
                    phase = .empty
                } else {
                    phase = .loaded(priceResults)
                    if let product = productResult {
                        if imageData != nil {
                            saveScan(product: product, items: shopItems)
                        } else if let url = videoURL {
                            await saveScanDeep(product: product, items: shopItems, videoURL: url)
                        }
                    }
                    // textQuery and re-sorts: ephemeral, not saved to history
                }
            } catch is CancellationError {
                // User navigated away before the response arrived — no UI update needed.
            } catch {
                phase = .error(error.localizedDescription)
            }
        }
        .onChange(of: sortMode) { _, _ in
            phase = .loading
            fetchID += 1
        }
        .onAppear {
            videoPlayer?.play()
            isPlaying = true
            setupTimeObserver()
        }
        .onDisappear {
            videoPlayer?.pause()
            teardownTimeObserver()
        }
        .onChange(of: showFrameResults) { _, showing in
            if !showing {
                frameImageData = nil
                frameScanUploadData = nil
            }
        }
        .navigationDestination(isPresented: $showFrameResults) {
            if let data = frameImageData {
                ResultsView(scanMode: .precision, imageData: data, uploadData: frameScanUploadData)
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

    // MARK: — Persistence

    private func saveScan(product: IdentifyResult, items: [ShopItem]) {
        let name = [product.brand, product.model].filter { !$0.isEmpty }.joined(separator: " ")
        let lowestPrice = items.min(by: { $0.extractedPrice < $1.extractedPrice })?.extractedPrice ?? 0
        let record = ScanRecord(
            productName: name.isEmpty ? product.category.capitalized : name,
            mode: scanMode == .precision ? "precision" : "deep",
            thumbnailData: downsampleImageData(imageData, maxDimension: 120),
            lowestPrice: lowestPrice,
            searchQuery: product.searchQuery
        )
        modelContext.insert(record)
    }

    private func saveScanDeep(product: IdentifyResult, items: [ShopItem], videoURL: URL) async {
        let name = [product.brand, product.model].filter { !$0.isEmpty }.joined(separator: " ")
        let lowestPrice = items.min(by: { $0.extractedPrice < $1.extractedPrice })?.extractedPrice ?? 0
        let thumbnailData = await BackendClient.extractThumbnail(from: videoURL)
        let record = ScanRecord(
            productName: name.isEmpty ? product.category.capitalized : name,
            mode: "deep",
            thumbnailData: thumbnailData,
            lowestPrice: lowestPrice,
            searchQuery: product.searchQuery
        )
        modelContext.insert(record)
    }

    /// Resize image to at most maxDimension px on the longest side, return JPEG data.
    private func downsampleImageData(_ data: Data?, maxDimension: CGFloat) -> Data? {
        guard let data, let image = UIImage(data: data) else { return nil }
        let scale = min(maxDimension / image.size.width, maxDimension / image.size.height, 1)
        guard scale < 1 else { return image.jpegData(compressionQuality: 0.7) }
        let newSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        let resized = renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: newSize)) }
        return resized.jpegData(compressionQuality: 0.7)
    }

    // MARK: — ShopItem → PriceResult

    private func mapToPriceResults(_ items: [ShopItem]) -> [PriceResult] {
        guard !items.isEmpty else { return [] }
        if sortMode == .reviews {
            // Backend already sorted by Bayesian score; first item is best reviewed
            return items.enumerated().map { index, item in
                PriceResult(
                    retailer: item.source,
                    price: item.price,
                    shipping: item.delivery,
                    isBest: index == 0,
                    link: item.link,
                    thumbnail: item.thumbnail,
                    rating: item.rating,
                    reviewCount: item.reviewCount,
                    title: item.title,
                    snippet: item.snippet,
                    productId: item.productId
                )
            }
        } else {
            let sorted = items.sorted { $0.extractedPrice < $1.extractedPrice }
            let bestPrice = sorted.first?.extractedPrice ?? 0
            return sorted.map { item in
                PriceResult(
                    retailer: item.source,
                    price: item.price,
                    shipping: item.delivery,
                    isBest: bestPrice > 0 && item.extractedPrice == bestPrice,
                    link: item.link,
                    thumbnail: item.thumbnail,
                    rating: item.rating,
                    reviewCount: item.reviewCount,
                    title: item.title,
                    snippet: item.snippet,
                    productId: item.productId
                )
            }
        }
    }

    // MARK: — Loaded

    private func loadedView(_ results: [PriceResult]) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                productHeader
                    .padding(.horizontal, Spacing.xl)
                sortToggle
                    .padding(.horizontal, Spacing.xl)
                VStack(spacing: Spacing.sm) {
                    ForEach(results) { productCard($0) }
                }
                .padding(.horizontal, Spacing.xl)
            }
            .padding(.top, Spacing.xl)
            .padding(.bottom, Spacing.xxxl)
        }
    }

    private var sortToggle: some View {
        Picker("Sort", selection: $sortMode) {
            ForEach(SortMode.allCases, id: \.self) { mode in
                Text(mode.label).tag(mode)
            }
        }
        .pickerStyle(.segmented)
    }

    @ViewBuilder
    private var productHeader: some View {
        if let player = videoPlayer {
            VStack(alignment: .leading, spacing: Spacing.md) {
                videoPlayerSection(player: player)
                productInfo
            }
        } else if let query = textQuery {
            HStack(spacing: Spacing.lg) {
                ZStack {
                    RoundedRectangle(cornerRadius: Radius.md)
                        .fill(Color.Brand.surfaceAlt)
                        .frame(width: 80, height: 80)
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 28))
                        .foregroundStyle(Color.Brand.accent)
                }
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text(query)
                        .font(Typography.headline)
                        .foregroundStyle(Color.Brand.textPrimary)
                        .lineLimit(2)
                    Text("Search results")
                        .font(Typography.caption)
                        .foregroundStyle(Color.Brand.textSecondary)
                    modeBadge
                }
            }
        } else if productPageURL != nil {
            HStack(spacing: Spacing.lg) {
                Group {
                    if let urlStr = identifyResult?.imageURL,
                       !urlStr.isEmpty,
                       let imgURL = URL(string: urlStr) {
                        AsyncImage(url: imgURL) { phase in
                            switch phase {
                            case .success(let image): image.resizable().scaledToFill()
                            default: thumbnailPlaceholder
                            }
                        }
                    } else {
                        ZStack {
                            Color.Brand.surfaceAlt
                            Image(systemName: "link")
                                .font(.system(size: 28))
                                .foregroundStyle(Color.Brand.accent)
                        }
                    }
                }
                .frame(width: 80, height: 80)
                .clipShape(RoundedRectangle(cornerRadius: Radius.md))
                productInfo
            }
        } else {
            HStack(spacing: Spacing.lg) {
                capturedImageThumbnail(size: 80)
                productInfo
            }
        }
    }

    private var productInfo: some View {
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

    private var modeBadge: some View {
        HStack(spacing: Spacing.xs) {
            Image(systemName: badgeIcon)
                .font(.system(size: 10, weight: .semibold))
            Text(badgeLabel)
                .font(Typography.caption.weight(.semibold))
        }
        .foregroundStyle(badgeColor)
    }

    private var badgeIcon: String {
        if productPageURL != nil { return "link" }
        if textQuery != nil { return "magnifyingglass" }
        return scanMode == .precision ? "camera.aperture" : "video.fill"
    }

    private var badgeLabel: String {
        if productPageURL != nil { return "Link Scan" }
        if textQuery != nil { return "Text Search" }
        return scanMode == .precision ? "Precision Scan" : "Deep Scan"
    }

    private var badgeColor: Color {
        scanMode == .deep && productPageURL == nil && textQuery == nil
            ? Color.Brand.scanDeep : Color.Brand.accent
    }

    private func productCard(_ result: PriceResult) -> some View {
        NavigationLink {
            ProductDetailView(result: result, sortMode: sortMode)
        } label: {
            priceRowContent(result)
        }
        .buttonStyle(.plain)
    }

    private func priceRowContent(_ result: PriceResult) -> some View {
        HStack(alignment: .top, spacing: Spacing.md) {
            productThumbnail(urlString: result.thumbnail, size: 60)

            VStack(alignment: .leading, spacing: Spacing.xs) {
                HStack(spacing: Spacing.sm) {
                    Text(result.title ?? result.retailer)
                        .font(Typography.callout.weight(.semibold))
                        .foregroundStyle(Color.Brand.textPrimary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    if result.isBest { bestBadge }
                }

                if result.title != nil {
                    Text(result.retailer)
                        .font(Typography.caption)
                        .foregroundStyle(Color.Brand.accent)
                }

                ratingRow(result)

                if let snippet = result.snippet {
                    Text(snippet)
                        .font(Typography.caption)
                        .foregroundStyle(Color.Brand.textSecondary)
                        .lineLimit(2)
                }
            }

            VStack(alignment: .trailing, spacing: Spacing.xs) {
                Text(result.price)
                    .font(Typography.callout.weight(.bold))
                    .foregroundStyle(result.isBest ? Color.Brand.success : Color.Brand.textPrimary)
                    .fixedSize()
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.Brand.textSecondary)
            }
            .padding(.top, 2)
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

    private func ratingRow(_ result: PriceResult) -> some View {
        HStack(spacing: Spacing.xs) {
            if let r = result.rating {
                Image(systemName: "star.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(Color(red: 1, green: 0.76, blue: 0))
                Text(String(format: "%.1f", r))
                    .font(Typography.caption)
                    .foregroundStyle(Color.Brand.textSecondary)
                if let count = result.reviewCount {
                    Text("(\(count.formatted()))")
                        .font(Typography.caption)
                        .foregroundStyle(Color.Brand.textSecondary)
                }
                if !result.shipping.isEmpty {
                    Text("·")
                        .font(Typography.caption)
                        .foregroundStyle(Color.Brand.textSecondary)
                }
            }
            if !result.shipping.isEmpty {
                Text(result.shipping)
                    .font(Typography.caption)
                    .foregroundStyle(Color.Brand.textSecondary)
            }
        }
    }

    private func productThumbnail(urlString: String, size: CGFloat) -> some View {
        Group {
            if let url = URL(string: urlString), !urlString.isEmpty {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    default:
                        thumbnailPlaceholder
                    }
                }
            } else {
                thumbnailPlaceholder
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: Radius.sm))
    }

    private var thumbnailPlaceholder: some View {
        ZStack {
            Color.Brand.surfaceAlt
            Image(systemName: "photo")
                .font(.system(size: 18))
                .foregroundStyle(Color.Brand.textSecondary.opacity(0.5))
        }
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
        .padding(.vertical, 2)
        .background(Color.Brand.success)
        .clipShape(Capsule())
    }

    // MARK: — Loading skeleton

    private var loadingView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                if let player = videoPlayer {
                    VStack(alignment: .leading, spacing: Spacing.md) {
                        videoPlayerSection(player: player)
                        ShimmerRect(height: 18).frame(width: 200)
                    }
                    .padding(.horizontal, Spacing.xl)
                } else if let query = textQuery {
                    HStack(spacing: Spacing.lg) {
                        ZStack {
                            RoundedRectangle(cornerRadius: Radius.md)
                                .fill(Color.Brand.surfaceAlt)
                                .frame(width: 80, height: 80)
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 28))
                                .foregroundStyle(Color.Brand.accent)
                        }
                        VStack(alignment: .leading, spacing: Spacing.sm) {
                            Text(query)
                                .font(Typography.callout.weight(.semibold))
                                .foregroundStyle(Color.Brand.textPrimary)
                                .lineLimit(1)
                            ShimmerRect(height: 14).frame(width: 120)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, Spacing.xl)
                } else if productPageURL != nil {
                    HStack(spacing: Spacing.lg) {
                        ZStack {
                            Color.Brand.surfaceAlt
                            Image(systemName: "link")
                                .font(.system(size: 28))
                                .foregroundStyle(Color.Brand.accent)
                        }
                        .frame(width: 80, height: 80)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.md))
                        VStack(alignment: .leading, spacing: Spacing.sm) {
                            ShimmerRect(height: 18).frame(width: 180)
                            ShimmerRect(height: 14).frame(width: 90)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, Spacing.xl)
                } else {
                    HStack(spacing: Spacing.lg) {
                        capturedImageThumbnail(size: 80)
                        VStack(alignment: .leading, spacing: Spacing.sm) {
                            ShimmerRect(height: 18).frame(width: 180)
                            ShimmerRect(height: 14).frame(width: 90)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, Spacing.xl)
                }

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
        HStack(alignment: .top, spacing: Spacing.md) {
            ShimmerRect(height: 60)
                .frame(width: 60)
                .clipShape(RoundedRectangle(cornerRadius: Radius.sm))
            VStack(alignment: .leading, spacing: Spacing.sm) {
                ShimmerRect(height: 15).frame(width: 180)
                ShimmerRect(height: 13).frame(width: 100)
                ShimmerRect(height: 13).frame(width: 140)
            }
            Spacer()
            ShimmerRect(height: 18).frame(width: 56)
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

    @ViewBuilder
    private func errorView(_ message: String) -> some View {
        if productPageURL != nil {
            VStack(spacing: Spacing.xl) {
                Image(systemName: "wifi.exclamationmark")
                    .font(.system(size: 52))
                    .foregroundStyle(Color.Brand.error)
                VStack(spacing: Spacing.sm) {
                    Text("Couldn't load prices")
                        .font(Typography.headline)
                        .foregroundStyle(Color.Brand.textPrimary)
                    Text(message)
                        .font(Typography.body)
                        .foregroundStyle(Color.Brand.textSecondary)
                        .multilineTextAlignment(.center)
                }
                Button("Try Again") {
                    phase = .loading
                    fetchID += 1
                }
                .font(Typography.callout.weight(.semibold))
                .foregroundStyle(Color.Brand.accentOn)
                .padding(.horizontal, Spacing.xxl)
                .padding(.vertical, Spacing.md)
                .background(Color.Brand.accent)
                .clipShape(RoundedRectangle(cornerRadius: Radius.md))

                Button("Search by name instead") {
                    prefillQuery = identifyResult?.model ?? ""
                    dismiss()
                }
                .font(Typography.callout.weight(.medium))
                .foregroundStyle(Color.Brand.accent)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(Spacing.xxl)
        } else if let player = videoPlayer {
            ScrollView {
                VStack(spacing: Spacing.xl) {
                    videoPlayerSection(player: player)
                        .padding(.horizontal, Spacing.xl)
                    VStack(spacing: Spacing.xl) {
                        Image(systemName: "wifi.exclamationmark")
                            .font(.system(size: 52))
                            .foregroundStyle(Color.Brand.error)
                        VStack(spacing: Spacing.sm) {
                            Text("Couldn't load prices")
                                .font(Typography.headline)
                                .foregroundStyle(Color.Brand.textPrimary)
                            Text(message)
                                .font(Typography.body)
                                .foregroundStyle(Color.Brand.textSecondary)
                                .multilineTextAlignment(.center)
                        }
                        Button("Try Again") {
                            phase = .loading
                            fetchID += 1
                        }
                        .font(Typography.callout.weight(.semibold))
                        .foregroundStyle(Color.Brand.accentOn)
                        .padding(.horizontal, Spacing.xxl)
                        .padding(.vertical, Spacing.md)
                        .background(Color.Brand.accent)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.md))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, Spacing.xl)
                }
                .padding(.top, Spacing.xl)
                .padding(.bottom, Spacing.xxxl)
            }
        } else {
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

    // MARK: — Video player with controls

    private func videoPlayerSection(player: AVPlayer) -> some View {
        VStack(spacing: Spacing.sm) {
            ZStack {
                PlayerLayerView(player: player)

                if !isPlaying, let frameData = pausedFrameData {
                    // Use cgImage dimensions (set by captureFrame): these are transform-corrected
                    // (appliesPreferredTrackTransform=true) so they always match the visual layout.
                    // presentationSize can return pre-transform (landscape) dims for portrait videos.
                    let vidSize = pausedVideoSize.width > 0
                        ? pausedVideoSize
                        : (player.currentItem?.presentationSize ?? CGSize(width: 16, height: 9))
                    InlineVideoCropOverlay(
                        frameData: frameData,
                        videoSize: vidSize,
                        onConfirm: { cropRect in
                            Task { await scanFrame(imageData: frameData, cropRect: cropRect) }
                        }
                    )
                }

                #if DEBUG
                if let preview = debugCropPreview {
                    VStack {
                        HStack {
                            Spacer()
                            VStack(spacing: 3) {
                                Text("SENT").font(.system(size: 9, weight: .bold)).foregroundStyle(.yellow)
                                Image(uiImage: preview)
                                    .resizable().scaledToFit()
                                    .frame(width: 80, height: 80)
                                    .background(.black)
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.yellow, lineWidth: 1.5))
                            }
                            .padding(6)
                            .background(.black.opacity(0.75))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .padding(6)
                            .onTapGesture { debugCropPreview = nil }
                        }
                        Spacer()
                    }
                }
                #endif
            }
            .frame(height: 200)
            .clipShape(RoundedRectangle(cornerRadius: Radius.md))

            HStack(spacing: Spacing.sm) {
                Button {
                    if isPlaying {
                        player.pause()
                        isPlaying = false
                        let time = player.currentTime()
                        Task { await captureFrame(at: time) }
                    } else {
                        player.play()
                        isPlaying = true
                        pausedFrameData = nil
                    }
                } label: {
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Color.Brand.textPrimary)
                        .frame(width: 28, height: 28)
                }

                Text(formatTime(playerCurrentTime))
                    .font(Typography.caption.monospacedDigit())
                    .foregroundStyle(Color.Brand.textSecondary)
                    .frame(width: 34, alignment: .leading)

                Slider(
                    value: Binding(
                        get: { playerCurrentTime },
                        set: { v in
                            playerCurrentTime = v
                            player.seek(
                                to: CMTime(seconds: v, preferredTimescale: 600),
                                toleranceBefore: .zero,
                                toleranceAfter: .zero
                            )
                        }
                    ),
                    in: 0...max(playerDuration, 1)
                )
                .tint(Color.Brand.scanDeep)

                Text(formatTime(playerDuration))
                    .font(Typography.caption.monospacedDigit())
                    .foregroundStyle(Color.Brand.textSecondary)
                    .frame(width: 34, alignment: .trailing)
            }
        }
    }

    private func setupTimeObserver() {
        guard let player = videoPlayer, timeObserverToken == nil else { return }
        let interval = CMTime(seconds: 0.1, preferredTimescale: 600)
        timeObserverToken = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak player] time in
            playerCurrentTime = time.seconds
            if let duration = player?.currentItem?.duration, duration.isNumeric {
                playerDuration = max(duration.seconds, 1)
            }
        }
    }

    private func teardownTimeObserver() {
        guard let token = timeObserverToken else { return }
        videoPlayer?.removeTimeObserver(token)
        timeObserverToken = nil
    }

    private func captureFrame(at time: CMTime) async {
        guard let url = videoURL else { return }
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        generator.maximumSize = CGSize(width: 1024, height: 1024)
        guard let (cgImage, _) = try? await generator.image(at: time) else { return }
        // Store the actual generated image dimensions — transform-corrected, aspect ratio is what
        // both the player and ImageCropper see. Do NOT use presentationSize: it can return the
        // pre-transform (landscape) size for portrait videos shot on iPhone.
        pausedVideoSize = CGSize(width: cgImage.width, height: cgImage.height)
        pausedFrameData = UIImage(cgImage: cgImage).jpegData(compressionQuality: 0.9)
        #if DEBUG
        print("[CropDebug] captureFrame: cgImage \(cgImage.width)×\(cgImage.height), pausedVideoSize=\(pausedVideoSize)")
        #endif
    }

    private func scanFrame(imageData: Data, cropRect: CGRect) async {
        #if DEBUG
        if let src = UIImage(data: imageData)?.cgImage {
            let pw = CGFloat(src.width), ph = CGFloat(src.height)
            let px = CGRect(
                x: cropRect.minX * pw, y: cropRect.minY * ph,
                width: cropRect.width * pw, height: cropRect.height * ph
            )
            print("[CropDebug] scanFrame: image \(Int(pw))×\(Int(ph))")
            print("[CropDebug] cropRect (normalized): \(String(format:"(%.3f,%.3f) \(String(format:"%.3f",cropRect.width))×%.3f",cropRect.minX,cropRect.minY,cropRect.height))")
            print("[CropDebug] pixelRect: (\(Int(px.minX)),\(Int(px.minY))) \(Int(px.width))×\(Int(px.height))")
        }
        #endif
        let uploadData = await ImageCropper.prepareForUpload(data: imageData, cropRect: cropRect)
        #if DEBUG
        if let preview = UIImage(data: uploadData) {
            let scale = Int(preview.scale)
            print("[CropDebug] upload image: \(Int(preview.size.width*preview.scale))×\(Int(preview.size.height*preview.scale)) @\(scale)x → \(uploadData.count/1024) KB")
            debugCropPreview = preview
        }
        #endif
        frameImageData = imageData
        frameScanUploadData = uploadData
        showFrameResults = true
    }

    private func formatTime(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let s = Int(seconds)
        return String(format: "%d:%02d", s / 60, s % 60)
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

// MARK: — AVPlayer layer wrapper (no native transport controls)

private struct PlayerLayerView: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> PlayerUIView {
        PlayerUIView(player: player)
    }

    func updateUIView(_ uiView: PlayerUIView, context: Context) {}
}

private final class PlayerUIView: UIView {
    private let playerLayer = AVPlayerLayer()

    init(player: AVPlayer) {
        super.init(frame: .zero)
        backgroundColor = .black
        playerLayer.player = player
        playerLayer.videoGravity = .resizeAspect
        layer.addSublayer(playerLayer)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        playerLayer.frame = bounds
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

// MARK: — Inline video crop overlay

/// Aspect-fit display rect of a video inside a container view.
/// videoAspect > viewAspect → letterbox (black bars top/bottom)
/// videoAspect < viewAspect → pillarbox (black bars left/right)
private func videoDisplayRect(videoSize: CGSize, viewSize: CGSize) -> CGRect {
    guard videoSize.width > 0, videoSize.height > 0,
          viewSize.width > 0, viewSize.height > 0
    else { return CGRect(origin: .zero, size: viewSize) }
    let va = videoSize.width / videoSize.height
    let vwa = viewSize.width / viewSize.height
    let size: CGSize = va > vwa
        ? CGSize(width: viewSize.width,       height: viewSize.width / va)
        : CGSize(width: viewSize.height * va, height: viewSize.height)
    return CGRect(
        x: (viewSize.width  - size.width)  / 2,
        y: (viewSize.height - size.height) / 2,
        width: size.width, height: size.height
    )
}

/// Crop overlay rendered directly on the paused video player.
/// `cropRect` is kept in normalized coords (0–1) relative to the video display area,
/// which matches `ImageCropper.prepareForUpload(data:cropRect:)` directly.
private struct InlineVideoCropOverlay: View {
    let frameData: Data
    let videoSize: CGSize
    let onConfirm: (CGRect) -> Void

    @State private var cropRect = CGRect(x: 0.1, y: 0.1, width: 0.8, height: 0.8)
    @State private var saliencyReady = false
    @State private var dragStart: CGRect? = nil
    @State private var userHasDragged = false   // prevents saliency from overwriting a manual drag
    @State private var isScanning = false

    private let handleSize: CGFloat = 22
    private let minFraction: CGFloat = 0.05

    var body: some View {
        GeometryReader { geo in
            let frame = videoDisplayRect(videoSize: videoSize, viewSize: geo.size)
            let vc    = viewCropRect(frame: frame)

            ZStack {
                // Dim surround — even-odd fill punches a transparent hole at vc
                Path { p in
                    p.addRect(CGRect(origin: .zero, size: geo.size))
                    p.addRect(vc)
                }
                .fill(Color.black.opacity(0.55), style: FillStyle(eoFill: true))
                .allowsHitTesting(false)

                // Rule-of-thirds grid
                gridLines(vc: vc)

                // Crop border
                Rectangle()
                    .strokeBorder(Color.white.opacity(0.9), lineWidth: 1.5)
                    .frame(width: vc.width, height: vc.height)
                    .position(x: vc.midX, y: vc.midY)
                    .allowsHitTesting(false)

                // Body drag — transparent fill captures touches in the interior
                Color.white.opacity(0.001)
                    .frame(
                        width:  max(1, vc.width  - handleSize),
                        height: max(1, vc.height - handleSize)
                    )
                    .position(x: vc.midX, y: vc.midY)
                    .gesture(bodyGesture(frame: frame))

                // Corner handles
                cornerHandle(.topLeft,    at: CGPoint(x: vc.minX, y: vc.minY), frame: frame)
                cornerHandle(.topRight,   at: CGPoint(x: vc.maxX, y: vc.minY), frame: frame)
                cornerHandle(.bottomLeft, at: CGPoint(x: vc.minX, y: vc.maxY), frame: frame)
                cornerHandle(.bottomRight,at: CGPoint(x: vc.maxX, y: vc.maxY), frame: frame)

                if !saliencyReady {
                    ProgressView().tint(.white)
                }

                // Scan button pinned to bottom of overlay
                VStack {
                    Spacer()
                    if isScanning {
                        ProgressView().tint(.white).padding(.bottom, 10)
                    } else {
                        Button {
                            #if DEBUG
                            let dbgFrame = videoDisplayRect(videoSize: videoSize, viewSize: geo.size)
                            let dbgVc    = viewCropRect(frame: dbgFrame)
                            print("[CropDebug] geo.size: \(geo.size)")
                            print("[CropDebug] videoSize: \(videoSize)")
                            print("[CropDebug] videoDisplayRect: \(dbgFrame)")
                            print("[CropDebug] vc (view coords): \(dbgVc)")
                            print("[CropDebug] cropRect sent (normalized): \(cropRect)")
                            #endif
                            isScanning = true
                            onConfirm(cropRect)
                        } label: {
                            Label("Scan this frame", systemImage: "camera.viewfinder")
                                .font(Typography.callout.weight(.semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 7)
                                .background(Color.Brand.accent)
                                .clipShape(Capsule())
                        }
                        .padding(.bottom, 10)
                    }
                }
            }
        }
        .task {
            let rect = await ImageCropper.saliencyRect(for: frameData)
            // Only apply saliency if the user hasn't already dragged to their own region.
            // Without this guard, Vision finishing after a drag snaps the rect back.
            if !userHasDragged {
                withAnimation(.spring(duration: 0.4)) { cropRect = rect }
            }
            saliencyReady = true
        }
    }

    private func viewCropRect(frame: CGRect) -> CGRect {
        CGRect(
            x: frame.minX + cropRect.minX * frame.width,
            y: frame.minY + cropRect.minY * frame.height,
            width: cropRect.width  * frame.width,
            height: cropRect.height * frame.height
        )
    }

    private func gridLines(vc: CGRect) -> some View {
        let tw = vc.width / 3, th = vc.height / 3
        return Path { p in
            for i in 1...2 {
                let x = vc.minX + tw * CGFloat(i)
                p.move(to: CGPoint(x: x, y: vc.minY))
                p.addLine(to: CGPoint(x: x, y: vc.maxY))
                let y = vc.minY + th * CGFloat(i)
                p.move(to: CGPoint(x: vc.minX, y: y))
                p.addLine(to: CGPoint(x: vc.maxX, y: y))
            }
        }
        .stroke(Color.white.opacity(0.3), lineWidth: 0.5)
        .allowsHitTesting(false)
    }

    private enum Corner { case topLeft, topRight, bottomLeft, bottomRight }

    private func cornerHandle(_ corner: Corner, at point: CGPoint, frame: CGRect) -> some View {
        Circle()
            .fill(Color.white)
            .frame(width: handleSize, height: handleSize)
            .shadow(color: .black.opacity(0.35), radius: 3)
            .position(point)
            .gesture(cornerGesture(corner, frame: frame))
    }

    private func bodyGesture(frame: CGRect) -> some Gesture {
        DragGesture()
            .onChanged { drag in
                userHasDragged = true
                if dragStart == nil { dragStart = cropRect }
                guard let start = dragStart else { return }
                let dx = drag.translation.width  / frame.width
                let dy = drag.translation.height / frame.height
                cropRect = CGRect(
                    x: min(max(start.minX + dx, 0), 1 - start.width),
                    y: min(max(start.minY + dy, 0), 1 - start.height),
                    width: start.width, height: start.height
                )
            }
            .onEnded { _ in dragStart = nil }
    }

    private func cornerGesture(_ corner: Corner, frame: CGRect) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { drag in
                userHasDragged = true
                if dragStart == nil { dragStart = cropRect }
                guard let start = dragStart else { return }
                let dx = drag.translation.width  / frame.width
                let dy = drag.translation.height / frame.height
                cropRect = adjustedRect(start: start, corner: corner, dx: dx, dy: dy)
            }
            .onEnded { _ in dragStart = nil }
    }

    private func adjustedRect(start: CGRect, corner: Corner, dx: CGFloat, dy: CGFloat) -> CGRect {
        var x0 = start.minX, y0 = start.minY
        var x1 = start.maxX, y1 = start.maxY
        switch corner {
        case .topLeft:
            x0 = min(max(x0 + dx, 0), x1 - minFraction)
            y0 = min(max(y0 + dy, 0), y1 - minFraction)
        case .topRight:
            x1 = min(max(x1 + dx, x0 + minFraction), 1)
            y0 = min(max(y0 + dy, 0), y1 - minFraction)
        case .bottomLeft:
            x0 = min(max(x0 + dx, 0), x1 - minFraction)
            y1 = min(max(y1 + dy, y0 + minFraction), 1)
        case .bottomRight:
            x1 = min(max(x1 + dx, x0 + minFraction), 1)
            y1 = min(max(y1 + dy, y0 + minFraction), 1)
        }
        return CGRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)
    }
}

// MARK: — Sample data (previews only)

extension PriceResult {
    static let samples: [PriceResult] = [
        PriceResult(retailer: "Amazon",   price: "$279.99", shipping: "Free",   isBest: true,  link: "", thumbnail: "", rating: 4.8, reviewCount: 12543, title: "Nike Air Force 1 Low White/White",      snippet: "Top-rated with fast Prime delivery. Highly rated by thousands of customers.", productId: "mock_amz_1"),
        PriceResult(retailer: "Walmart",  price: "$289.95", shipping: "$5.99",  isBest: false, link: "", thumbnail: "", rating: 4.6, reviewCount: 3871,  title: "Nike Air Force 1 Low Men's Shoes",      snippet: "Save with everyday low prices and free 2-day shipping on eligible orders.",  productId: "mock_wmt_2"),
        PriceResult(retailer: "Best Buy", price: "$299.99", shipping: "Free",   isBest: false, link: "", thumbnail: "", rating: 4.7, reviewCount: 1102,  title: "Nike Air Force 1 '07",                  snippet: "Expert advice and price match guarantee at Best Buy.",                       productId: "mock_bbuy_5"),
        PriceResult(retailer: "eBay",     price: "$259.00", shipping: "$12.00", isBest: false, link: "", thumbnail: "", rating: nil, reviewCount: nil,   title: "Nike Air Force 1 Low (Used - Excellent)", snippet: nil,                                                                         productId: nil),
        PriceResult(retailer: "Target",   price: "$319.99", shipping: "Free",   isBest: false, link: "", thumbnail: "", rating: 4.5, reviewCount: 918,   title: "Nike Air Force 1 Low Sneaker",          snippet: "Free shipping on orders over $35 or free same-day pickup.",                productId: "mock_tgt_3"),
    ]
}

#Preview("Loaded — Precision") { NavigationStack { ResultsView() }.modelContainer(for: ScanRecord.self, inMemory: true) }
#Preview("Loaded — Deep")      { NavigationStack { ResultsView(scanMode: .deep) }.modelContainer(for: ScanRecord.self, inMemory: true) }
#Preview("Loading")            { NavigationStack { ResultsView(phase: .loading) }.modelContainer(for: ScanRecord.self, inMemory: true) }
#Preview("Empty")              { NavigationStack { ResultsView(phase: .empty) }.modelContainer(for: ScanRecord.self, inMemory: true) }
#Preview("Error")              { NavigationStack { ResultsView(phase: .error("Network connection lost.")) }.modelContainer(for: ScanRecord.self, inMemory: true) }
