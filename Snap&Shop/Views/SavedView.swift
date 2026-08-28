import SwiftUI
import SwiftData

struct SavedView: View {
    @Query(sort: \SavedItem.savedDate, order: .reverse) private var items: [SavedItem]
    @Environment(\.modelContext) private var modelContext
    @State private var alertItem: SavedItem? = nil

    var body: some View {
        NavigationStack {
            ZStack {
                Color.Brand.background.ignoresSafeArea()
                if items.isEmpty {
                    emptyState
                } else {
                    itemList
                }
            }
            .navigationTitle("Saved")
            .navigationBarTitleDisplayMode(.large)
        }
        .sheet(item: $alertItem) { item in
            AddAlertSheet(item: item)
        }
    }

    private var emptyState: some View {
        VStack(spacing: Spacing.lg) {
            Spacer()
            Image(systemName: "bookmark.slash")
                .font(.system(size: 52))
                .foregroundStyle(Color.Brand.textSecondary)
            Text("No Saved Items")
                .font(Typography.headline)
                .foregroundStyle(Color.Brand.textPrimary)
            Text("Tap the bookmark icon on any result to save it here.")
                .font(Typography.body)
                .foregroundStyle(Color.Brand.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Spacing.xl)
            Spacer()
        }
    }

    private var itemList: some View {
        List {
            ForEach(items) { item in
                NavigationLink {
                    ResultsView(textQuery: item.searchQuery)
                } label: {
                    savedRow(item)
                }
                .listRowBackground(Color.Brand.surface)
                .listRowSeparatorTint(Color.Brand.border)
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) { delete(item) } label: {
                        Label("Delete", systemImage: "trash")
                    }
                    Button { alertItem = item } label: {
                        Label("Alert", systemImage: "bell")
                    }
                    .tint(Color.Brand.accent)
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
    }

    private func savedRow(_ item: SavedItem) -> some View {
        HStack(spacing: Spacing.md) {
            Group {
                if let data = item.thumbnailData, let image = UIImage(data: data) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    Color.Brand.surfaceAlt
                        .overlay(
                            Image(systemName: "photo")
                                .foregroundStyle(Color.Brand.textSecondary)
                        )
                }
            }
            .frame(width: 56, height: 56)
            .clipShape(RoundedRectangle(cornerRadius: Radius.sm))

            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(item.productName)
                    .font(Typography.callout.weight(.semibold))
                    .foregroundStyle(Color.Brand.textPrimary)
                    .lineLimit(2)
                Text(item.source)
                    .font(Typography.caption)
                    .foregroundStyle(Color.Brand.textSecondary)

                HStack(spacing: Spacing.sm) {
                    Text(item.savedPrice.formatted(.currency(code: "USD")))
                        .font(Typography.caption.weight(.medium))
                        .foregroundStyle(Color.Brand.textPrimary)

                    if let current = item.currentLowestPrice, current < item.savedPrice {
                        HStack(spacing: 2) {
                            Image(systemName: "arrow.down")
                                .font(.system(size: 9, weight: .bold))
                            Text(current.formatted(.currency(code: "USD")))
                                .font(Typography.caption.weight(.semibold))
                        }
                        .foregroundStyle(Color.Brand.success)
                        .padding(.horizontal, Spacing.xs)
                        .padding(.vertical, 2)
                        .background(Color.Brand.success.opacity(0.12))
                        .clipShape(Capsule())
                    }
                }
            }

            Spacer()

            Button { alertItem = item } label: {
                Image(systemName: "bell")
                    .font(.system(size: 16))
                    .foregroundStyle(Color.Brand.accent)
                    .frame(width: 36, height: 36)
                    .background(Color.Brand.accent.opacity(0.1))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Set price alert for \(item.productName)")
        }
        .padding(.vertical, Spacing.xs)
    }

    private func delete(_ item: SavedItem) {
        let itemId = item.id
        let alertDescriptor = FetchDescriptor<PriceAlert>(
            predicate: #Predicate { $0.savedItemId == itemId }
        )
        if let related = try? modelContext.fetch(alertDescriptor) {
            related.forEach { modelContext.delete($0) }
        }
        modelContext.delete(item)
    }
}

#Preview {
    SavedView()
        .modelContainer(
            try! ModelContainer(
                for: Schema([ScanRecord.self, SavedItem.self, PriceAlert.self]),
                configurations: ModelConfiguration(isStoredInMemoryOnly: true)
            )
        )
}
