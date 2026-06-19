import SwiftData
import SwiftUI

private enum HomeDisplayMode: String, CaseIterable, Identifiable {
    case reminders
    case notes

    var id: String { rawValue }

    var title: String {
        switch self {
        case .reminders:
            return "Erinnerungen"
        case .notes:
            return "Notizen"
        }
    }

    var systemImage: String {
        switch self {
        case .reminders:
            return "bell"
        case .notes:
            return "doc.text"
        }
    }

    var gradient: LinearGradient {
        switch self {
        case .reminders:
            return LinearGradient(
                colors: [Color(red: 0.55, green: 0.30, blue: 1.0), Color(red: 1.0, green: 0.23, blue: 0.58)],
                startPoint: .leading,
                endPoint: .trailing
            )
        case .notes:
            return LinearGradient(
                colors: [Color(red: 1.0, green: 0.45, blue: 0.12), Color(red: 1.0, green: 0.23, blue: 0.58)],
                startPoint: .leading,
                endPoint: .trailing
            )
        }
    }
}

struct HomeView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \MemoItem.createdAt, order: .reverse) private var items: [MemoItem]
    @Query(sort: \MemoCategoryItem.sortOrder) private var categories: [MemoCategoryItem]

    @StateObject private var viewModel = HomeViewModel()
    @State private var isCapturePresented = false
    @State private var selectedMode: HomeDisplayMode = .reminders
    @State private var isSearchVisible = false
    @State private var errorMessage: String?

    private let imageStorage = ImageStorageService.shared

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            backgroundView
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    headerView

                    if isSearchVisible {
                        searchField
                    }

                    modePicker
                    categoryChips
                    content
                }
                .padding(.horizontal, 24)
                .padding(.top, 22)
                .padding(.bottom, 120)
            }

            CaptureButton {
                isCapturePresented = true
            }
            .padding(.trailing, 28)
            .padding(.bottom, 34)
        }
        .toolbar(.hidden, for: .navigationBar)
        .preferredColorScheme(.dark)
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
        let groups = viewModel.sectionGroups(from: modeItems, categories: categories)

        if items.isEmpty {
            emptyState(
                title: "Noch keine Memos",
                systemImage: "sparkles",
                message: "Tippe auf den großen Button, um deine erste Notiz oder Erinnerung zu erfassen."
            )
        } else if groups.isEmpty {
            emptyState(
                title: "Keine Ergebnisse",
                systemImage: "magnifyingglass",
                message: "Versuche einen anderen Suchbegriff oder entferne den Filter."
            )
        } else {
            LazyVStack(alignment: .leading, spacing: 18) {
                ForEach(groups) { group in
                    VStack(alignment: .leading, spacing: 12) {
                        Text(group.section.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.58))
                            .textCase(.uppercase)

                        ForEach(group.items) { item in
                            NavigationLink {
                                DetailView(item: item)
                            } label: {
                                MemoCardView(
                                    item: item,
                                    category: category(for: item),
                                    onToggleCompleted: {
                                        toggleCompleted(item)
                                    },
                                    onDelete: {
                                        delete(item)
                                    }
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .animation(.snappy(duration: 0.2), value: viewModel.searchText)
            .animation(.snappy(duration: 0.2), value: viewModel.selectedCategoryRawValue)
            .animation(.snappy(duration: 0.2), value: selectedMode)
        }
    }

    private var backgroundView: some View {
        LinearGradient(
            colors: [
                Color(red: 0.03, green: 0.03, blue: 0.06),
                Color(red: 0.06, green: 0.04, blue: 0.10),
                Color(red: 0.02, green: 0.02, blue: 0.04)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var headerView: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Willkommen zurück!")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.white.opacity(0.58))

                Text("\(modeItems.count) \(selectedMode.title)")
                    .font(.system(size: 44, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.72)

                if completedCount > 0 {
                    Text("\(completedCount) erledigt")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.green)
                }
            }

            Spacer()

            HStack(spacing: 10) {
                iconCircle("magnifyingglass") {
                    withAnimation(.snappy(duration: 0.2)) {
                        isSearchVisible.toggle()
                    }
                }

                NavigationLink {
                    SettingsView()
                } label: {
                    Image(systemName: "gearshape")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(width: 52, height: 52)
                        .background(Color.white.opacity(0.08), in: Circle())
                        .overlay(Circle().strokeBorder(Color.white.opacity(0.10)))
                }
                .buttonStyle(.plain)

                iconCircle("mic.fill") {
                    isCapturePresented = true
                }
                .background(
                    LinearGradient(
                        colors: [Color(red: 0.52, green: 0.30, blue: 1.0), Color(red: 1.0, green: 0.23, blue: 0.58)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    in: Circle()
                )
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.white.opacity(0.55))

            TextField("Suchen", text: $viewModel.searchText)
                .textInputAutocapitalization(.never)
                .foregroundStyle(.white)

            if !viewModel.searchText.isEmpty {
                Button {
                    viewModel.searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.white.opacity(0.5))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 54)
        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.white.opacity(0.10))
        }
    }

    private var modePicker: some View {
        HStack(spacing: 14) {
            ForEach(HomeDisplayMode.allCases) { mode in
                Button {
                    selectedMode = mode
                } label: {
                    Label(mode.title, systemImage: mode.systemImage)
                        .font(.headline)
                        .foregroundStyle(selectedMode == mode ? .white : .white.opacity(0.52))
                        .frame(maxWidth: .infinity)
                        .frame(height: 68)
                        .background {
                            if selectedMode == mode {
                                mode.gradient
                            } else {
                                Color.white.opacity(0.07)
                            }
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .strokeBorder(Color.white.opacity(selectedMode == mode ? 0.0 : 0.10))
                        }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var categoryChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                categoryChip(
                    title: "Alle",
                    systemImage: "square.stack.3d.up",
                    color: Color(red: 0.12, green: 0.66, blue: 1.0),
                    isSelected: viewModel.selectedCategoryRawValue == nil
                ) {
                    viewModel.selectedCategoryRawValue = nil
                }

                ForEach(categories, id: \.id) { category in
                    categoryChip(
                        title: category.displayName,
                        systemImage: category.systemImage,
                        color: category.tint,
                        isSelected: viewModel.selectedCategoryRawValue == category.id
                    ) {
                        viewModel.selectedCategoryRawValue = category.id
                    }
                }

                NavigationLink {
                    SettingsView()
                } label: {
                    Image(systemName: "plus")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Color(red: 0.65, green: 0.39, blue: 1.0))
                        .frame(width: 54, height: 54)
                        .background(Color.white.opacity(0.07), in: Circle())
                        .overlay(Circle().strokeBorder(Color.white.opacity(0.10)))
                }
                .buttonStyle(.plain)
            }
            .padding(.vertical, 2)
        }
    }

    private var modeItems: [MemoItem] {
        switch selectedMode {
        case .reminders:
            return items.filter { $0.hasReminder || ($0.isCompleted && $0.reminderDate != nil) }
        case .notes:
            return items.filter { !$0.hasReminder }
        }
    }

    private var completedCount: Int {
        modeItems.filter(\.isCompleted).count
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

    private func deleteItems(at offsets: IndexSet, in sectionItems: [MemoItem]) {
        offsets.map { sectionItems[$0] }.forEach(delete)
    }

    private func iconCircle(_ systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 52, height: 52)
                .background(Color.white.opacity(0.08), in: Circle())
                .overlay(Circle().strokeBorder(Color.white.opacity(0.10)))
        }
        .buttonStyle(.plain)
    }

    private func categoryChip(
        title: String,
        systemImage: String,
        color: Color,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(isSelected ? .white : .white.opacity(0.62))
                .padding(.horizontal, 18)
                .frame(height: 54)
                .background(isSelected ? color : Color.white.opacity(0.07), in: Capsule())
                .overlay {
                    Capsule()
                        .strokeBorder(isSelected ? color.opacity(0) : color.opacity(0.42), lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
    }

    private func emptyState(title: String, systemImage: String, message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.72))

            Text(title)
                .font(.headline)
                .foregroundStyle(.white)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.58))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(28)
        .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(Color.white.opacity(0.10))
        }
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
