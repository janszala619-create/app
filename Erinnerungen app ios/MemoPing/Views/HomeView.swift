import SwiftData
import SwiftUI
import UIKit

struct HomeView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \MemoItem.createdAt, order: .reverse) private var items: [MemoItem]
    @Query(sort: \MemoCategoryItem.sortOrder) private var categories: [MemoCategoryItem]

    @StateObject private var viewModel = HomeViewModel()
    @State private var isCapturePresented = false
    @State private var errorMessage: String?

    private let imageStorage = ImageStorageService.shared

    var body: some View {
        ZStack(alignment: .bottom) {
            content
                .safeAreaInset(edge: .bottom) {
                    Color.clear.frame(height: 100)
                }

            CaptureButton {
                isCapturePresented = true
            }
            .padding(.bottom, 22)
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
        .searchable(text: $viewModel.searchText, prompt: "Memos durchsuchen")
        .background(Color(.systemGroupedBackground))
        .sheet(isPresented: $isCapturePresented) {
            CaptureView { isCapturePresented = false }
        }
        .task {
            do {
                try MemoCategoryItem.seedDefaultsIfNeeded(in: modelContext)
            } catch {
                errorMessage = error.localizedDescription
            }

            // Widget-Snapshot beim App-Start aktuell halten
            MemoWidgetSnapshotUpdater.refresh(in: modelContext)

            // Benachrichtigungen entfernen, die zu gelöschten oder erledigten Memos gehören
            let validIdentifiers = Set(
                items
                    .filter { $0.hasReminder && !$0.isCompleted }
                    .map { $0.id.uuidString }
            )
            await NotificationService.shared.removeOrphanedNotifications(validIdentifiers: validIdentifiers)
        }
        .alert("Hinweis", isPresented: errorBinding) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            Text("MemoPing")
                .font(.headline)
        }
        ToolbarItem(placement: .topBarTrailing) {
            categoryFilterMenu
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        let groups = viewModel.sectionGroups(from: items, categories: categories)

        if items.isEmpty {
            emptyState(
                title: "Noch keine Memos",
                subtitle: "Tippe auf den Button unten, um deine erste Notiz oder Erinnerung zu erfassen.",
                systemImage: "sparkles"
            )
        } else if groups.isEmpty {
            emptyState(
                title: "Keine Ergebnisse",
                subtitle: "Versuche einen anderen Suchbegriff oder entferne den Filter.",
                systemImage: "magnifyingglass"
            )
        } else {
            ScrollView {
                // Fix A: Header-Card mit Tagesübersicht
                summaryHeader(groups: groups)
                    .padding(.horizontal, 16)
                    .padding(.top, 12)

                // Fix A: Filter-Chips
                categoryFilterChips
                    .padding(.horizontal, 16)
                    .padding(.top, 8)

                // Memo-Liste
                LazyVStack(spacing: 0, pinnedViews: .sectionHeaders) {
                    ForEach(groups) { group in
                        Section {
                            ForEach(group.items) { item in
                                NavigationLink {
                                    DetailView(item: item)
                                } label: {
                                    MemoCardView(
                                        item: item,
                                        category: MemoCategoryItem.item(for: item.categoryRawValue, in: categories)
                                    )
                                }
                                .buttonStyle(.plain)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 4)
                                .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                    Button {
                                        toggleCompleted(item)
                                    } label: {
                                        Label(
                                            item.isCompleted ? "Offen" : "Erledigt",
                                            systemImage: item.isCompleted ? "circle" : "checkmark"
                                        )
                                    }
                                    .tint(.green)
                                }
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    Button(role: .destructive) {
                                        delete(item)
                                    } label: {
                                        Label("Löschen", systemImage: "trash")
                                    }
                                }
                            }
                        } header: {
                            sectionHeader(group.section.title)
                        }
                    }
                }
                .padding(.top, 8)
                .animation(.snappy(duration: 0.2), value: viewModel.searchText)
                .animation(.snappy(duration: 0.2), value: viewModel.selectedCategoryRawValue)
            }
        }
    }

    // MARK: - Summary Header (Fix A)

    private func summaryHeader(groups: [MemoSectionGroup]) -> some View {
        let openCount = groups.filter { $0.section != .completed }.flatMap(\.items).count
        let doneCount = groups.first(where: { $0.section == .completed })?.items.count ?? 0
        let highCount = groups.flatMap(\.items).filter { $0.priority == .high && !$0.isCompleted }.count

        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(todayLabel)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                        .tracking(0.5)

                    Text("Dein Überblick")
                        .font(.title2.weight(.bold))
                }
                Spacer()
            }

            HStack(spacing: 10) {
                statPill(count: openCount, label: "Offen", systemImage: "circle", tint: .accentColor)
                statPill(count: doneCount, label: "Erledigt", systemImage: "checkmark.circle.fill", tint: .green)
                if highCount > 0 {
                    statPill(count: highCount, label: "Dringend", systemImage: "exclamationmark.circle.fill", tint: .red)
                }
            }
        }
        .padding(16)
        .background(
            Color(.secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06))
        }
    }

    private static let todayLabelFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Date.germanLocale
        formatter.dateFormat = "EEEE, d. MMMM"
        return formatter
    }()

    private var todayLabel: String {
        Self.todayLabelFormatter.string(from: Date())
    }

    private func statPill(count: Int, label: String, systemImage: String, tint: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 0) {
                Text("\(count)")
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(.primary)
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(tint.opacity(0.1), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    // MARK: - Category Filter Chips (Fix A)

    private var categoryFilterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                filterChip(label: "Alle", systemImage: "tray.2", isActive: viewModel.selectedCategoryRawValue == nil) {
                    viewModel.selectedCategoryRawValue = nil
                }

                ForEach(categories, id: \.id) { category in
                    filterChip(
                        label: category.displayName,
                        systemImage: category.systemImage,
                        isActive: viewModel.selectedCategoryRawValue == category.id,
                        tint: category.tint
                    ) {
                        viewModel.selectedCategoryRawValue = (viewModel.selectedCategoryRawValue == category.id) ? nil : category.id
                    }
                }
            }
            .padding(.vertical, 2)
        }
    }

    private func filterChip(
        label: String,
        systemImage: String,
        isActive: Bool,
        tint: Color = .accentColor,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(label, systemImage: systemImage)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(isActive ? activeChipTextColor(for: tint) : tint)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(
                    isActive ? tint : tint.opacity(0.12),
                    in: Capsule()
                )
        }
        .buttonStyle(.plain)
        .animation(.snappy(duration: 0.15), value: isActive)
    }

    /// Weiße Schrift ist auf hellen Tints (Gelb, Orange, Teal) nicht lesbar —
    /// helle Chip-Hintergründe bekommen deshalb dunkle Schrift.
    private func activeChipTextColor(for tint: Color) -> Color {
        tint.isBrightTint ? .black : .white
    }

    // MARK: - Section Header

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .tracking(0.5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 4)
            .background(Color(.systemGroupedBackground))
    }

    // MARK: - Empty State

    private func emptyState(title: String, subtitle: String, systemImage: String) -> some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: systemImage)
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(.tertiary)
            Text(title)
                .font(.title3.weight(.semibold))
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Spacer()
        }
    }

    // MARK: - Category Filter Menu (Toolbar)

    private var categoryFilterMenu: some View {
        Menu {
            Button {
                viewModel.selectedCategoryRawValue = nil
            } label: {
                Label(
                    "Alle Kategorien",
                    systemImage: viewModel.selectedCategoryRawValue == nil ? "checkmark" : "tray.2"
                )
            }
            Divider()
            ForEach(categories, id: \.id) { category in
                Button {
                    viewModel.selectedCategoryRawValue = category.id
                } label: {
                    Label(
                        category.displayName,
                        systemImage: viewModel.selectedCategoryRawValue == category.id ? "checkmark" : category.systemImage
                    )
                }
            }
        } label: {
            Image(systemName: viewModel.selectedCategoryRawValue == nil
                  ? "line.3.horizontal.decrease.circle"
                  : "line.3.horizontal.decrease.circle.fill")
        }
        .accessibilityLabel("Kategorie filtern")
    }

    // MARK: - Bindings & Actions

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )
    }

    private func toggleCompleted(_ item: MemoItem) {
        let previous = item.isCompleted
        item.isCompleted.toggle()
        item.updatedAt = Date()

        Task { @MainActor in
            do {
                if item.isCompleted {
                    NotificationService.shared.cancelReminder(for: item)

                    // Auch den synchronisierten Kalendertermin beenden,
                    // sonst laufen dessen Alarme und Wiederholungen endlos weiter.
                    if let eventIdentifier = item.calendarEventIdentifier {
                        try? await CalendarSyncService.shared.deleteEvent(with: eventIdentifier)
                        item.calendarEventIdentifier = nil
                        item.syncsToCalendar = false
                    }
                } else if item.hasReminder {
                    try await NotificationService.shared.scheduleReminder(for: item)
                }
                try modelContext.save()
                MemoWidgetSnapshotUpdater.refresh(in: modelContext)
            } catch {
                item.isCompleted = previous
                item.updatedAt = Date()
                errorMessage = error.localizedDescription
            }
        }
    }

    private func delete(_ item: MemoItem) {
        Task { @MainActor in
            NotificationService.shared.cancelReminder(for: item)

            if let eventIdentifier = item.calendarEventIdentifier {
                try? await CalendarSyncService.shared.deleteEvent(with: eventIdentifier)
            }

            imageStorage.deleteImages(fileNames: item.imageFileNames)
            modelContext.delete(item)
            do {
                try modelContext.save()
                MemoWidgetSnapshotUpdater.refresh(in: modelContext)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

private extension Color {
    /// Relative Luminanz als Entscheidungsgrundlage für lesbare Schrift auf Tint-Flächen.
    var isBrightTint: Bool {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        guard UIColor(self).getRed(&red, green: &green, blue: &blue, alpha: &alpha) else {
            return false
        }

        return (0.2126 * red + 0.7152 * green + 0.0722 * blue) > 0.55
    }
}

#Preview {
    HomeView()
        .modelContainer(for: [MemoItem.self, MemoCategoryItem.self], inMemory: true)
}
