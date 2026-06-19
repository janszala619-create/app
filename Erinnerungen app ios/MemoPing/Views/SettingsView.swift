import EventKit
import SwiftData
import SwiftUI
import UserNotifications

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \MemoCategoryItem.sortOrder) private var categories: [MemoCategoryItem]
    @Query private var memoItems: [MemoItem]

    @State private var notificationStatus: UNAuthorizationStatus = .notDetermined
    @State private var calendarStatus: EKAuthorizationStatus = .notDetermined
    @State private var iCloudState: ICloudAccountState = .couldNotDetermine
    @State private var errorMessage: String?
    @State private var categoryEditor: CategoryEditorDraft?

    var body: some View {
        Form {
            Section("Benachrichtigungen") {
                HStack {
                    Label("Status", systemImage: "bell")
                    Spacer()
                    Text(NotificationService.statusText(for: notificationStatus))
                        .foregroundStyle(.secondary)
                }

                Text("Erinnerungen werden als lokale iOS-Benachrichtigungen auf diesem iPhone geplant.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if notificationStatus == .denied {
                    Label("Benachrichtigungen sind deaktiviert.", systemImage: "bell.slash")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else if notificationStatus == .notDetermined {
                    Label("Benachrichtigungen wurden noch nicht angefragt.", systemImage: "questionmark.circle")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Button {
                    requestNotifications()
                } label: {
                    Label("Benachrichtigungen erlauben", systemImage: "bell.badge")
                }
                .disabled(notificationStatus == .authorized)

                #if DEBUG
                Button {
                    scheduleDebugReminder()
                } label: {
                    Label("Test-Erinnerung in 10 Sekunden", systemImage: "timer")
                }
                #endif
            }

            Section("iCloud Sync") {
                HStack {
                    Label("Status", systemImage: "icloud")
                    Spacer()
                    Text(iCloudState.displayText)
                        .foregroundStyle(iCloudState == .available ? Color.green : Color.secondary)
                }

                Text("MemoPing synchronisiert Memos über iCloud, wenn iCloud auf diesem Gerät aktiviert ist.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(iCloudState.detailText)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                #if DEBUG
                Text(ICloudSyncService.cloudKitContainerIdentifier)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                #endif
            }

            Section("iOS-Kalender") {
                HStack {
                    Label("Status", systemImage: "calendar")
                    Spacer()
                    Text(CalendarSyncService.statusText(for: calendarStatus))
                        .foregroundStyle(calendarStatusAllowsSync ? Color.green : Color.secondary)
                }

                Text("MemoPing kann Erinnerungen als Termine im iOS-Kalender erstellen, aktualisieren und beim Löschen wieder entfernen.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button {
                    requestCalendarAccess()
                } label: {
                    Label("Kalenderzugriff erlauben", systemImage: "calendar.badge.plus")
                }
                .disabled(calendarStatusAllowsSync)
            }

            Section("Datenschutz") {
                Label("Die Synchronisation läuft über Apples iCloud/CloudKit. MemoPing verwendet keinen eigenen Server.", systemImage: "lock")
                Text("Spracherkennung wird über iOS bereitgestellt. Bilder bleiben in dieser Version als lokale Dateien auf dem jeweiligen Gerät gespeichert.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Kategorien") {
                ForEach(categories, id: \.id) { category in
                    HStack(spacing: 12) {
                        Label(category.displayName, systemImage: category.systemImage)
                            .foregroundStyle(category.tint)

                        if category.isDefault {
                            Text("Standard")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(Color.secondary.opacity(0.12), in: Capsule())
                        }

                        Spacer()

                        Button {
                            categoryEditor = CategoryEditorDraft(category: category)
                        } label: {
                            Image(systemName: "pencil")
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Kategorie bearbeiten")

                        Button(role: .destructive) {
                            deleteCategory(category)
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Kategorie löschen")
                    }
                }

                Button {
                    categoryEditor = CategoryEditorDraft()
                } label: {
                    Label("Kategorie hinzufügen", systemImage: "plus")
                }
            }

            Section("App-Info") {
                HStack {
                    Text("MemoPing")
                    Spacer()
                    Text("Version 1.0")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Einstellungen")
        .task {
            seedDefaultCategoriesIfNeeded()
            await refreshNotificationStatus()
            refreshCalendarStatus()
            await refreshICloudStatus()
        }
        .sheet(item: $categoryEditor) { draft in
            CategoryEditorView(draft: draft) { updatedDraft in
                saveCategory(updatedDraft)
            }
        }
        .alert("Hinweis", isPresented: errorBinding) {
            Button("OK", role: .cancel) {
                errorMessage = nil
            }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )
    }

    private var calendarStatusAllowsSync: Bool {
        switch calendarStatus {
        case .authorized, .fullAccess:
            return true
        default:
            return false
        }
    }

    private func requestNotifications() {
        Task { @MainActor in
            do {
                let granted = try await NotificationService.shared.requestAuthorization()
                await refreshNotificationStatus()

                if !granted {
                    errorMessage = "Benachrichtigungen wurden nicht erlaubt. Erinnerungen können erst nach Aktivierung in den iOS-Einstellungen geplant werden."
                }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func refreshNotificationStatus() async {
        notificationStatus = await NotificationService.shared.getAuthorizationStatus()
    }

    private func refreshCalendarStatus() {
        calendarStatus = CalendarSyncService.shared.authorizationStatus()
    }

    private func requestCalendarAccess() {
        Task { @MainActor in
            do {
                let granted = try await CalendarSyncService.shared.requestAccess()
                refreshCalendarStatus()

                if !granted {
                    errorMessage = "Kalenderzugriff wurde nicht erlaubt. Erinnerungen bleiben trotzdem lokal in MemoPing verfügbar."
                }
            } catch {
                refreshCalendarStatus()
                errorMessage = error.localizedDescription
            }
        }
    }

    private func refreshICloudStatus() async {
        iCloudState = await ICloudSyncService.shared.accountState()
    }

    private func seedDefaultCategoriesIfNeeded() {
        do {
            try MemoCategoryItem.seedDefaultsIfNeeded(in: modelContext)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func saveCategory(_ draft: CategoryEditorDraft) {
        let name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            errorMessage = "Bitte gib einen Kategorienamen ein."
            return
        }

        do {
            if let categoryID = draft.categoryID,
               let category = categories.first(where: { $0.id == categoryID }) {
                category.name = name
                category.systemImage = draft.systemImage
                category.tintRawValue = draft.tintRawValue
                category.updatedAt = Date()
            } else {
                let nextSortOrder = (categories.map(\.sortOrder).max() ?? -1) + 1
                modelContext.insert(
                    MemoCategoryItem(
                        name: name,
                        systemImage: draft.systemImage,
                        tintRawValue: draft.tintRawValue,
                        sortOrder: nextSortOrder
                    )
                )
            }

            try modelContext.save()
            categoryEditor = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func deleteCategory(_ category: MemoCategoryItem) {
        let categoryID = category.id
        memoItems
            .filter { $0.categoryRawValue == categoryID }
            .forEach {
                $0.categoryRawValue = nil
                $0.updatedAt = Date()
            }

        modelContext.delete(category)

        do {
            try modelContext.save()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    #if DEBUG
    private func scheduleDebugReminder() {
        Task { @MainActor in
            do {
                try await NotificationService.shared.scheduleDebugReminder()
                await refreshNotificationStatus()
                errorMessage = "Test-Erinnerung wurde für in 10 Sekunden geplant."
            } catch {
                await refreshNotificationStatus()
                errorMessage = error.localizedDescription
            }
        }
    }
    #endif
}

private struct CategoryEditorDraft: Identifiable {
    let id = UUID()
    var categoryID: String?
    var name: String
    var systemImage: String
    var tintRawValue: String

    init(
        categoryID: String? = nil,
        name: String = "",
        systemImage: String = "tag",
        tintRawValue: String = "blue"
    ) {
        self.categoryID = categoryID
        self.name = name
        self.systemImage = systemImage
        self.tintRawValue = tintRawValue
    }

    init(category: MemoCategoryItem) {
        self.categoryID = category.id
        self.name = category.displayName
        self.systemImage = category.systemImage
        self.tintRawValue = category.tintRawValue
    }
}

private struct CategoryEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft: CategoryEditorDraft

    let onSave: (CategoryEditorDraft) -> Void

    init(draft: CategoryEditorDraft, onSave: @escaping (CategoryEditorDraft) -> Void) {
        _draft = State(initialValue: draft)
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Kategorie") {
                    TextField("Name", text: $draft.name)

                    Picker("Symbol", selection: $draft.systemImage) {
                        ForEach(MemoCategoryItem.availableSystemImages, id: \.self) { systemImage in
                            Label(systemImage, systemImage: systemImage)
                                .tag(systemImage)
                        }
                    }

                    Picker("Farbe", selection: $draft.tintRawValue) {
                        ForEach(MemoCategoryItem.availableTintRawValues, id: \.self) { tintRawValue in
                            Label(MemoCategoryItem.tintName(for: tintRawValue), systemImage: "circle.fill")
                                .foregroundStyle(MemoCategoryItem.tint(for: tintRawValue))
                                .tag(tintRawValue)
                        }
                    }
                }
            }
            .navigationTitle(draft.categoryID == nil ? "Neue Kategorie" : "Kategorie bearbeiten")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Sichern") {
                        onSave(draft)
                    }
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        SettingsView()
    }
    .modelContainer(for: [MemoItem.self, MemoCategoryItem.self], inMemory: true)
}
