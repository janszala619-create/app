import SwiftData
import SwiftUI

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
                    Color.clear.frame(height: 104)
                }

            CaptureButton {
                isCapturePresented = true
            }
            .padding(.bottom, 22)
        }
        .navigationTitle("MemoPing")
        .searchable(text: $viewModel.searchText, prompt: "Suchen")
        .background(Color(.systemGroupedBackground))
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                categoryFilterMenu
            }
        }
        .sheet(isPresented: $isCapturePresented) {
            CaptureView {
                isCapturePresented = false
            }
        }
        .alert("Hinweis", isPresented: errorBinding) {
            Button("OK", role: .cancel) {
                errorMessage = nil
            }
        } message: {
            Text(errorMessage ?? "")
        }
        .task(id: reminderPlanSignature) {
            await planSyncedRemindersIfNeeded()
        }
        .task {
            seedDefaultCategoriesIfNeeded()
        }
        .task(id: widgetSnapshotSignature) {
            MemoWidgetSnapshotUpdater.update(from: items)
        }
    }

    @ViewBuilder
    private var content: some View {
        let groups = viewModel.sectionGroups(from: items, categories: categories)

        if items.isEmpty {
            ContentUnavailableView(
                "Noch keine Memos",
                systemImage: "sparkles",
                description: Text("Tippe auf den großen Button, um deine erste Notiz oder Erinnerung zu erfassen.")
            )
        } else if groups.isEmpty {
            ContentUnavailableView(
                "Keine Ergebnisse gefunden.",
                systemImage: "magnifyingglass",
                description: Text("Versuche einen anderen Suchbegriff oder entferne den Filter.")
            )
        } else {
            List {
                ForEach(groups) { group in
                    Section(group.section.title) {
                        ForEach(group.items) { item in
                            NavigationLink {
                                DetailView(item: item)
                            } label: {
                                MemoCardView(item: item, category: category(for: item)) {
                                    toggleCompleted(item)
                                }
                            }
                            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                Button {
                                    toggleCompleted(item)
                                } label: {
                                    Label(item.isCompleted ? "Offen" : "Erledigt", systemImage: item.isCompleted ? "circle" : "checkmark")
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
                        .onDelete { offsets in
                            deleteItems(at: offsets, in: group.items)
                        }
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .animation(.snappy(duration: 0.2), value: viewModel.searchText)
            .animation(.snappy(duration: 0.2), value: viewModel.selectedCategoryRawValue)
        }
    }

    private var categoryFilterMenu: some View {
        Menu {
            Button {
                viewModel.selectedCategoryRawValue = nil
            } label: {
                Label("Alle Kategorien", systemImage: viewModel.selectedCategoryRawValue == nil ? "checkmark" : "line.3.horizontal.decrease.circle")
            }

            ForEach(categories, id: \.id) { category in
                Button {
                    viewModel.selectedCategoryRawValue = category.id
                } label: {
                    Label(category.displayName, systemImage: viewModel.selectedCategoryRawValue == category.id ? "checkmark" : category.systemImage)
                }
            }
        } label: {
            Label(selectedCategoryTitle, systemImage: "line.3.horizontal.decrease.circle")
        }
        .accessibilityLabel("Kategorie filtern")
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )
    }

    private var reminderPlanSignature: String {
        items
            .filter { $0.hasReminder && !$0.isCompleted && $0.reminderDate != nil }
            .map { "\($0.id.uuidString)-\($0.reminderDate?.timeIntervalSince1970 ?? 0)-\($0.reminderRepeatRawValue ?? "")-\($0.reminderLeadTimeRawValue ?? "")" }
            .joined(separator: "|")
    }

    private var widgetSnapshotSignature: String {
        items
            .map { item in
                [
                    item.id.uuidString,
                    item.title,
                    "\(item.hasReminder)",
                    "\(item.isCompleted)",
                    "\(item.reminderDate?.timeIntervalSince1970 ?? 0)"
                ].joined(separator: "-")
            }
            .joined(separator: "|")
    }

    private var selectedCategoryTitle: String {
        guard let rawValue = viewModel.selectedCategoryRawValue else {
            return "Filter"
        }

        return MemoCategoryItem.item(for: rawValue, in: categories)?.displayName ?? "Filter"
    }

    private func deleteItems(at offsets: IndexSet, in sectionItems: [MemoItem]) {
        offsets.map { sectionItems[$0] }.forEach(delete)
    }

    private func category(for item: MemoItem) -> MemoCategoryItem? {
        MemoCategoryItem.item(for: item.categoryRawValue, in: categories)
    }

    private func seedDefaultCategoriesIfNeeded() {
        do {
            try MemoCategoryItem.seedDefaultsIfNeeded(in: modelContext)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func toggleCompleted(_ item: MemoItem) {
        let previousCompletionState = item.isCompleted
        let previousCalendarSyncState = item.syncsToCalendar
        let previousCalendarEventIdentifier = item.calendarEventIdentifier
        item.isCompleted.toggle()

        if item.isCompleted {
            item.syncsToCalendar = false
            item.calendarEventIdentifier = nil
        }

        item.updatedAt = Date()

        Task { @MainActor in
            do {
                if item.isCompleted {
                    NotificationService.shared.cancelReminder(for: item)
                    try? await CalendarSyncService.shared.deleteEvent(with: previousCalendarEventIdentifier)
                } else if item.hasReminder {
                    try await NotificationService.shared.scheduleReminder(for: item)

                    if item.syncsToCalendar {
                        item.calendarEventIdentifier = try await CalendarSyncService.shared.saveEvent(for: item)
                    }
                }
                try modelContext.save()
                MemoWidgetSnapshotUpdater.update(from: items)
            } catch {
                item.isCompleted = previousCompletionState
                item.syncsToCalendar = previousCalendarSyncState
                item.calendarEventIdentifier = previousCalendarEventIdentifier
                item.updatedAt = Date()
                errorMessage = error.localizedDescription
            }
        }
    }

    private func delete(_ item: MemoItem) {
        Task { @MainActor in
            NotificationService.shared.cancelReminder(for: item)
            try? await CalendarSyncService.shared.deleteEvent(with: item.calendarEventIdentifier)
            imageStorage.deleteImages(fileNames: item.imageFileNames)
            modelContext.delete(item)

            do {
                try modelContext.save()
                MemoWidgetSnapshotUpdater.update(from: items)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func planSyncedRemindersIfNeeded() async {
        let notificationStatus = await NotificationService.shared.getAuthorizationStatus()
        guard notificationStatus == .authorized || notificationStatus == .provisional || notificationStatus == .ephemeral else {
            return
        }

        for item in items where item.hasReminder && !item.isCompleted {
            guard item.reminderDate != nil else { continue }

            do {
                try await NotificationService.shared.scheduleReminder(for: item)
            } catch {
                #if DEBUG
                print("MemoPing: Lokale Erinnerung konnte nach Sync nicht geplant werden: \(error)")
                #endif
            }
        }
    }
}

#Preview {
    HomeView()
        .modelContainer(for: [MemoItem.self, MemoCategoryItem.self], inMemory: true)
}
