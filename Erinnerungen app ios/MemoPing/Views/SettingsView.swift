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
        ScrollView {
            VStack(spacing: 14) {
                heroCard
                notificationsCard
                syncCard
                calendarCard
                privacyCard
                categoriesCard
                appInfoCard
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .padding(.bottom, 32)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Einstellungen")
        .navigationBarTitleDisplayMode(.large)
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
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // MARK: - Hero Card

    private var heroCard: some View {
        HStack(spacing: 14) {
            Image(systemName: "gear")
                .font(.title2.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 48, height: 48)
                .background(Color.accentColor.gradient, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text("Einstellungen")
                    .font(.title3.weight(.bold))
                Text("Berechtigungen, Sync & Kategorien")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .settingsCard()
    }

    // MARK: - Benachrichtigungen

    private var notificationsCard: some View {
        settingsSection(title: "Benachrichtigungen", systemImage: "bell.badge", tint: .accentColor) {
            statusRow(
                title: "Status",
                value: NotificationService.statusText(for: notificationStatus),
                tint: notificationStatus == .authorized ? .green : .orange
            )

            Divider()

            Text("Erinnerungen werden lokal auf diesem iPhone geplant.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if notificationStatus == .denied {
                infoNote("Benachrichtigungen sind deaktiviert. In iOS-Einstellungen aktivieren.", systemImage: "bell.slash", tint: .orange)
            } else if notificationStatus == .notDetermined {
                infoNote("Benachrichtigungen wurden noch nicht angefragt.", systemImage: "questionmark.circle", tint: .secondary)
            }

            if notificationStatus != .authorized {
                Button { requestNotifications() } label: {
                    Label("Benachrichtigungen erlauben", systemImage: "bell.badge")
                        .font(.subheadline.weight(.medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .foregroundStyle(.white)
                        .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
            }

            #if DEBUG
            Button { scheduleDebugReminder() } label: {
                Label("Test-Erinnerung in 10 Sek.", systemImage: "timer")
                    .font(.subheadline.weight(.medium))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .foregroundStyle(.accentColor)
                    .background(Color.accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .buttonStyle(.plain)
            #endif
        }
    }

    // MARK: - iCloud Sync

    private var syncCard: some View {
        settingsSection(title: "iCloud Sync", systemImage: "icloud", tint: .blue) {
            statusRow(
                title: "iCloud",
                value: iCloudState.displayText,
                tint: iCloudState == .available ? .green : .orange
            )

            Divider()

            Text("Memos werden über Apples iCloud/CloudKit synchronisiert, wenn iCloud auf diesem Gerät aktiv ist.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Text(iCloudState.detailText)
                .font(.caption)
                .foregroundStyle(.tertiary)

            #if DEBUG
            Text(ICloudSyncService.cloudKitContainerIdentifier)
                .font(.caption2)
                .foregroundStyle(.tertiary)
            #endif
        }
    }

    // MARK: - Kalender

    private var calendarCard: some View {
        settingsSection(title: "iOS-Kalender", systemImage: "calendar.badge.plus", tint: .orange) {
            statusRow(
                title: "Status",
                value: CalendarSyncService.statusText(for: calendarStatus),
                tint: calendarStatusAllowsSync ? .green : .orange
            )

            Divider()

            Text("Erinnerungen können als Termine im iOS-Kalender erstellt und aktualisiert werden.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if !calendarStatusAllowsSync {
                Button { requestCalendarAccess() } label: {
                    Label("Kalenderzugriff erlauben", systemImage: "calendar.badge.plus")
                        .font(.subheadline.weight(.medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .foregroundStyle(.white)
                        .background(Color.orange, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Datenschutz

    private var privacyCard: some View {
        settingsSection(title: "Datenschutz", systemImage: "lock.shield", tint: .green) {
            VStack(alignment: .leading, spacing: 10) {
                infoNote("Kein eigener Server — alles bleibt auf deinem Gerät.", systemImage: "checkmark.shield", tint: .green)
                infoNote("Spracherkennung wird über iOS bereitgestellt.", systemImage: "waveform", tint: .secondary)
                infoNote("Bilder werden lokal als Dateien gespeichert.", systemImage: "photo", tint: .secondary)
            }
        }
    }

    // MARK: - Kategorien

    private var categoriesCard: some View {
        settingsSection(title: "Kategorien", systemImage: "tag", tint: .purple) {
            if categories.isEmpty {
                Label("Noch keine Kategorien vorhanden.", systemImage: "tray")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 8) {
                    ForEach(categories, id: \.id) { category in
                        categoryRow(category)
                        if category.id != categories.last?.id {
                            Divider()
                        }
                    }
                }
            }

            Button {
                categoryEditor = CategoryEditorDraft()
            } label: {
                Label("Kategorie hinzufügen", systemImage: "plus")
                    .font(.subheadline.weight(.medium))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .foregroundStyle(.accentColor)
                    .background(Color.accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - App Info

    private var appInfoCard: some View {
        settingsSection(title: "App", systemImage: "app.badge", tint: .secondary) {
            statusRow(title: "RemindlyAI", value: "Version 1.0", tint: .secondary)
            Divider()
            statusRow(title: "Memos gesamt", value: "\(memoItems.count)", tint: .secondary)
        }
    }

    // MARK: - Reusable Komponenten

    private func settingsSection<Content: View>(
        title: String,
        systemImage: String,
        tint: Color,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(tint, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                Text(title)
                    .font(.headline)
            }

            content()
        }
        .settingsCard()
    }

    private func statusRow(title: String, value: String, tint: Color) -> some View {
        HStack {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }

    private func infoNote(_ text: String, systemImage: String, tint: Color) -> some View {
        Label(text, systemImage: systemImage)
            .font(.subheadline)
            .foregroundStyle(tint)
    }

    private func categoryRow(_ category: MemoCategoryItem) -> some View {
        HStack(spacing: 12) {
            Image(systemName: category.systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(category.tint)
                .frame(width: 32, height: 32)
                .background(category.tint.opacity(0.12), in: Circle())

            Text(category.displayName)
                .font(.subheadline.weight(.medium))

            if category.isDefault {
                Text("Standard")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Color(.tertiarySystemGroupedBackground), in: Capsule())
            }

            Spacer()

            Button {
                categoryEditor = CategoryEditorDraft(category: category)
            } label: {
                Image(systemName: "pencil")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(width: 32, height: 32)
                    .background(Color(.tertiarySystemGroupedBackground), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Kategorie bearbeiten")

            Button(role: .destructive) {
                deleteCategory(category)
            } label: {
                Image(systemName: "trash")
                    .font(.subheadline)
                    .foregroundStyle(.red)
                    .frame(width: 32, height: 32)
                    .background(Color.red.opacity(0.1), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Kategorie löschen")
        }
        .padding(.vertical, 4)
    }

    // MARK: - Bindings & Helpers

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )
    }

    private var calendarStatusAllowsSync: Bool {
        switch calendarStatus {
        case .authorized, .fullAccess: return true
        default: return false
        }
    }

    // MARK: - Actions

    private func requestNotifications() {
        Task { @MainActor in
            do {
                let granted = try await NotificationService.shared.requestAuthorization()
                await refreshNotificationStatus()
                if !granted {
                    errorMessage = "Benachrichtigungen wurden nicht erlaubt. Bitte in den iOS-Einstellungen aktivieren."
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
                    errorMessage = "Kalenderzugriff nicht erteilt. Erinnerungen bleiben trotzdem lokal verfügbar."
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
                errorMessage = "Test-Erinnerung in 10 Sekunden geplant."
            } catch {
                await refreshNotificationStatus()
                errorMessage = error.localizedDescription
            }
        }
    }
    #endif
}

// MARK: - Card Extension

private extension View {
    func settingsCard() -> some View {
        self
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                Color(.secondarySystemGroupedBackground),
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.06))
            }
    }
}

// MARK: - Category Editor

private struct CategoryEditorDraft: Identifiable {
    let id = UUID()
    var categoryID: String?
    var name: String
    var systemImage: String
    var tintRawValue: String

    init(categoryID: String? = nil, name: String = "", systemImage: String = "tag", tintRawValue: String = "blue") {
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
            ScrollView {
                VStack(spacing: 14) {
                    // Name
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Name")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)
                            .tracking(0.4)
                        TextField("Kategoriename", text: $draft.name)
                            .font(.headline)
                            .padding(12)
                            .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .padding(16)
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                    // Symbol
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Symbol")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)
                            .tracking(0.4)

                        Picker("Symbol", selection: $draft.systemImage) {
                            ForEach(MemoCategoryItem.availableSystemImages, id: \.self) { img in
                                Label(img, systemImage: img).tag(img)
                            }
                        }
                        .pickerStyle(.menu)
                    }
                    .padding(16)
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                    // Farbe
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Farbe")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)
                            .tracking(0.4)

                        Picker("Farbe", selection: $draft.tintRawValue) {
                            ForEach(MemoCategoryItem.availableTintRawValues, id: \.self) { raw in
                                Label(MemoCategoryItem.tintName(for: raw), systemImage: "circle.fill")
                                    .foregroundStyle(MemoCategoryItem.tint(for: raw))
                                    .tag(raw)
                            }
                        }
                        .pickerStyle(.menu)
                    }
                    .padding(16)
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                    // Vorschau
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Vorschau")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)
                            .tracking(0.4)

                        HStack(spacing: 10) {
                            Image(systemName: draft.systemImage)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(MemoCategoryItem.tint(for: draft.tintRawValue))
                                .frame(width: 36, height: 36)
                                .background(MemoCategoryItem.tint(for: draft.tintRawValue).opacity(0.12), in: Circle())

                            Text(draft.name.isEmpty ? "Kategoriename" : draft.name)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(draft.name.isEmpty ? .secondary : .primary)
                        }
                    }
                    .padding(16)
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .padding(16)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(draft.categoryID == nil ? "Neue Kategorie" : "Kategorie bearbeiten")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Sichern") { onSave(draft) }
                        .fontWeight(.semibold)
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
