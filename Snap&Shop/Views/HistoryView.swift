import SwiftUI
import SwiftData

struct HistoryView: View {
    @Query(sort: \ScanRecord.date, order: .reverse) private var records: [ScanRecord]
    @Environment(\.modelContext) private var modelContext
    @State private var searchText = ""

    private var filteredRecords: [ScanRecord] {
        guard !searchText.isEmpty else { return records }
        return records.filter { $0.productName.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        NavigationStack {
            Group {
                if records.isEmpty {
                    emptyView
                } else {
                    listView
                }
            }
            .navigationTitle("History")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Image("AppLogo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 28, height: 28)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                clearButton
            }
            .background(Color.Brand.background.ignoresSafeArea())
        }
    }

    // MARK: — List

    private var listView: some View {
        List {
            ForEach(filteredRecords) { record in
                historyRow(record)
                    .listRowBackground(Color.Brand.surface)
                    .listRowSeparatorTint(Color.Brand.border)
            }
            .onDelete { offsets in
                let toDelete = offsets.map { filteredRecords[$0] }
                toDelete.forEach { modelContext.delete($0) }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .searchable(text: $searchText, prompt: "Search products")
    }

    private func historyRow(_ record: ScanRecord) -> some View {
        HStack(spacing: Spacing.md) {
            // Thumbnail
            Group {
                if let data = record.thumbnailData, let uiImage = UIImage(data: data) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                } else {
                    ZStack {
                        Color.Brand.surfaceAlt
                        Image(systemName: "photo")
                            .foregroundStyle(Color.Brand.textSecondary)
                    }
                }
            }
            .frame(width: 52, height: 52)
            .clipShape(RoundedRectangle(cornerRadius: Radius.sm))

            // Name + meta
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(record.productName)
                    .font(Typography.callout.weight(.semibold))
                    .foregroundStyle(Color.Brand.textPrimary)
                    .lineLimit(1)
                HStack(spacing: Spacing.xs) {
                    modeBadge(record.mode)
                    Text(record.date, style: .date)
                        .font(Typography.caption)
                        .foregroundStyle(Color.Brand.textSecondary)
                }
            }

            Spacer()

            // Lowest price
            Text("$\(record.lowestPrice, specifier: "%.2f")")
                .font(Typography.callout.weight(.semibold))
                .foregroundStyle(Color.Brand.accent)
        }
        .padding(.vertical, Spacing.xs)
    }

    private func modeBadge(_ mode: String) -> some View {
        let isDeep = mode == "deep"
        return HStack(spacing: 3) {
            Image(systemName: isDeep ? "video.fill" : "camera.aperture")
                .font(.system(size: 9, weight: .semibold))
            Text(isDeep ? "Deep" : "Precision")
                .font(Typography.caption.weight(.medium))
        }
        .foregroundStyle(isDeep ? .white : Color.Brand.accentOn)
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, 2)
        .background(isDeep ? Color.Brand.scanDeep : Color.Brand.accent)
        .clipShape(Capsule())
    }

    // MARK: — Empty

    private var emptyView: some View {
        VStack(spacing: Spacing.xl) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 52))
                .foregroundStyle(Color.Brand.textSecondary)
            VStack(spacing: Spacing.sm) {
                Text("No scans yet")
                    .font(Typography.headline)
                    .foregroundStyle(Color.Brand.textPrimary)
                Text("Your scan history will appear here.")
                    .font(Typography.body)
                    .foregroundStyle(Color.Brand.textSecondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(Spacing.xxl)
    }

    // MARK: — Toolbar

    private var clearButton: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button(role: .destructive) {
                withAnimation { records.forEach { modelContext.delete($0) } }
            } label: {
                Text("Clear")
                    .font(Typography.callout)
                    .foregroundStyle(Color.Brand.error)
            }
            .disabled(records.isEmpty)
        }
    }
}

// MARK: — Previews

#Preview("With Records") {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: ScanRecord.self, configurations: config)
    let samples: [(String, String, Double, Int)] = [
        ("Sony WH-1000XM5 Headphones", "precision", 279.99, 0),
        ("Apple AirPods Pro 2",         "deep",      189.00, 1),
        ("Samsung 65\" QLED TV",        "deep",      899.00, 3),
    ]
    for (name, mode, price, daysAgo) in samples {
        container.mainContext.insert(ScanRecord(
            date: Calendar.current.date(byAdding: .day, value: -daysAgo, to: .now)!,
            productName: name,
            mode: mode,
            thumbnailData: nil,
            lowestPrice: price,
            searchQuery: name
        ))
    }
    return HistoryView().modelContainer(container)
}

#Preview("Empty") {
    HistoryView()
        .modelContainer(for: ScanRecord.self, inMemory: true)
}
