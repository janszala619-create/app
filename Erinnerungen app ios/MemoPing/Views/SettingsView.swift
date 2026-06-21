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
            VStack(alignment: .leading, spacing: 16) {
                settingsHeader

                settingsCard(title: "Benachrichtigungen", systemImage: "bell.badge", tint: RemindlyStyle.cyan) {
                    StatusRow(
                        title: "Status",
                        value: NotificationService.statusText(for: notificationStatus),
                        tint: notificationStatus == .authorized ? RemindlyStyle.success : RemindlyStyle.warning
                    )

                    Text("Erinnerungen werden lokal auf diesem iPhone geplant.")
                        .font(.subheadline)
                        .foregroundStyle(RemindlyStyle.mutedText)

                    if notificationStatus == .denied {
                        noteLine("Benachrichtigungen sind deaktiviert.", systemImage: "bell.slash")
                    } else if notificationStatus == .notDetermined {
                        noteLine("Benachrichtigungen wurden noch nicht angefragt.", systemImage: "questionmark.circle")
                    }

                    Button {
                        requestNotifications()
                    } label: {
                        Label("Benachrichtigungen erlauben", systemImage: "bell.badge")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(notificationStatus == .authorized)

                    #if DEBUG
                    Button {
                        scheduleDebugReminder()
                    } label: {
                        Label("Test-Erinnerung in 10 Sekunden", systemImage: "timer")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    #endif
                }

                settingsCard(title: "Sync", systemImage: "icloud", tint: RemindlyStyle.accent) {
                    StatusRow(
                        title: "iCloud",
                        value: iCloudState.displayText,
                        tint: iCloudState == .available ? RemindlyStyle.success : RemindlyStyle.warning
                    )

                    Text("Memos werden über Apples iCloud/CloudKit synchronisiert, wenn iCloud auf diesem Gerät aktiv ist.")
                        .font(.subheadline)
                        .foregroundStyle(RemindlyStyle.mutedText)

                    Text(iCloudState.detailText)
                        .font(.caption)
                        .foregroundStyle(RemindlyStyle.faintText)

                    #if DEBUG
                    Text(ICloudSyncService.cloudKitContainerIdentifier)
                        .font(.caption2)
                        .foregroundStyle(RemindlyStyle.faintText)
                    #endif
                }

                settingsCard(title: "iOS-Kalender", systemImage: "calendar.badge.plus", tint: RemindlyStyle.warning) {
                    StatusRow(
                        title: "Status",
                        value: CalendarSyncService.statusText(for: calendarStatus),
                        tint: calendarStatusAllowsSync ? RemindlyStyle.success : RemindlyStyle.warning
                    )

                    Text("Erinnerungen können als Termine erstellt, aktualisiert und beim Löschen wieder entfernt werden.")
                        .font(.subheadline)
                        .foregroundStyle(RemindlyStyle.mutedText)

                    Button {
                        requestCalendarAccess()
                    } label: {
                        Label("Kalenderzugriff erlauben", systemImage: "calendar.badge.plus")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(calendarStatusAllowsSync)
                }

                settingsCard(title: "Datenschutz", systemImage: "lock.shield", tint: RemindlyStyle.success) {
                    noteLine("RemindlyAi verwendet keinen eigenen Server.", systemImage: "checkmark.shield")
                    noteLine("Spracherkennung wird über iOS bereitgestellt.", systemImage: "waveform")
                    noteLine("Bilder bleiben in dieser Version als lokale Dateien auf dem Gerät.", systemImage: "photo")
                }

                settingsCard(title: "Kategorien", systemImage: "tag", tint: RemindlyStyle.pink) {
                    ForEach(categories, id: \.id) { category in
                        categoryRow(category)
                    }

                    Button {
                        categoryEditor = CategoryEditorDraft()
                    } label: {
                        Label("Kategorie hinzufügen", systemImage: "plus")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }

                settingsCard(title: "App", systemImage: "app.badge", tint: RemindlyStyle.cyan) {
                    StatusRow(title: "RemindlyAi", value: "Version 1.0", tint: RemindlyStyle.mutedText)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)
            .padding(.bottom, 32)
        }
        .background(RemindlyStyle.backgroundGradient.ignoresSafeArea())
        .tint(RemindlyStyle.accent)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarBackground(Color.black.opacity(0.36), for: .navigationBar)
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

    private var settingsHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Einstellungen")
                .font(.system(size: 36, weight: .black, design: .rounded))
                .foregroundStyle(.white)

            Text("Berechtigungen, Sync und Kategorien")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(RemindlyStyle.mutedText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
    }

    private func settingsCard<Content: View>(
        title: String,
        systemImage: String,
        tint: Color,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(RemindlyStyle.iconFill(tint), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                Text(title)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.white)
            }

            content()
        }
        .padding(18)
        .remindlyCard()
    }

    private func noteLine(_ text: String, systemImage: String) -> some View {
        Label(text, systemImage: systemImage)
            .font(.subheadline)
            .foregroundStyle(RemindlyStyle.mutedText)
    }

    private func categoryRow(_ category: MemoCategoryItem) -> some View {
        HStack(spacing: 12) {
            Image(systemName: category.systemImage)
                .font(.headline.weight(.semibold))
                .foregroundStyle(category.tint)
                .frame(width: 34, height: 34)
                .background(category.tint.opacity(0.14), in: Circle())

            Text(category.displayName)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.white)

            if category.isDefault {
                Text("Standard")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(RemindlyStyle.mutedText)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(RemindlyStyle.elevatedFill, in: Capsule())
            }

            Spacer()

            Button {
                categoryEditor = CategoryEditorDraft(category: category)
            } label: {
                Image(systemName: "pencil")
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Kategorie bearbeiten")

            Button(role: .destructive) {
                deleteCategory(category)
            } label: {
                Image(systemName: "trash")
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Kategorie löschen")
        }
        .padding(10)
        .background(Color.black.opacity(0.16), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
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
                    errorMessage = "Kalenderzugriff wurde nicht erlaubt. Erinnerungen bleiben trotzdem lokal in RemindlyAi verfügbar."
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

private struct StatusRow: View {
    let title: String
    let value: String
    let tint: Color

    var body: some View {
        HStack(spacing: 12) {
            Text(title)
                .foregroundStyle(RemindlyStyle.mutedText)

            Spacer()

            Text(value)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .font(.subheadline)
    }
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
                .listRowBackground(RemindlyStyle.cardFill)
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .background(RemindlyStyle.backgroundGradient.ignoresSafeArea())
            .tint(RemindlyStyle.accent)
            .navigationTitle(draft.categoryID == nil ? "Neue Kategorie" : "Kategorie bearbeiten")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarBackground(Color.black.opacity(0.36), for: .navigationBar)
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

#Preview("StatusRow States") {
    VStack(spacing: 14) {
        StatusRow(title: "Status", value: "Erlaubt", tint: RemindlyStyle.success)
        StatusRow(title: "iCloud", value: "Nicht angemeldet", tint: RemindlyStyle.warning)
        StatusRow(title: "Kalender", value: "Deaktiviert", tint: RemindlyStyle.danger)
        StatusRow(title: "RemindlyAi", value: "Version 1.0", tint: RemindlyStyle.mutedText)
    }
    .padding(18)
    .remindlyCard()
    .padding()
    .background(RemindlyStyle.backgroundGradient)
    .preferredColorScheme(.dark)
}
