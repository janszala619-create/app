import SwiftData
import SwiftUI
import UIKit

private struct DetailImage: Identifiable {
    let fileName: String
    let image: UIImage
    var id: String { fileName }
}

struct DetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    @Bindable var item: MemoItem

    @Query(sort: \MemoCategoryItem.sortOrder) private var categories: [MemoCategoryItem]

    @State private var isEditing = false
    @State private var errorMessage: String?
    @State private var selectedImage: DetailImage?
    @State private var showDeleteConfirmation = false
    @State private var loadedThumbnails: [String: UIImage] = [:]
    @State private var didLoadThumbnails = false

    private let imageStorage = ImageStorageService.shared

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                heroSection
                metaSection
                reminderSection
                textSection
                imagesSection
                detectedSection
                actionSection
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .padding(.bottom, 32)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Details")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: item.imageFileNames) {
            await loadThumbnails()
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(isEditing ? "Sichern" : "Bearbeiten") {
                    isEditing ? saveChanges() : (isEditing = true)
                }
                .fontWeight(isEditing ? .semibold : .regular)
            }
        }
        .alert("Hinweis", isPresented: errorBinding) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
        .confirmationDialog("Memo wirklich löschen?", isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
            Button("Löschen", role: .destructive) { deleteMemo() }
            Button("Abbrechen", role: .cancel) {}
        }
        .sheet(item: $selectedImage) { detailImage in
            NavigationStack {
                imageDetailView(detailImage)
                    .navigationTitle("Bild")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Schließen") { selectedImage = nil }
                        }
                    }
            }
        }
    }

    // MARK: - Hero Section

    private var heroSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Quelle + Status-Badges
            HStack(spacing: 8) {
                sourceBadge
                if item.isCompleted {
                    statusBadge("Erledigt", systemImage: "checkmark.circle.fill", tint: .green)
                }
                Spacer()
            }

            // Titel
            if isEditing {
                TextField("Titel", text: $item.title)
                    .font(.title2.weight(.bold))
                    .padding(10)
                    .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            } else {
                Text(item.title)
                    .font(.title2.weight(.bold))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .foregroundStyle(item.isCompleted ? .secondary : .primary)
                    .strikethrough(item.isCompleted)
            }

            // Erstellt-Info
            Text("Erstellt \(item.createdAt.germanFormatted(date: .abbreviated, time: .shortened))")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06))
        }
    }

    @ViewBuilder
    private var sourceBadge: some View {
        Label(item.sourceType.displayName, systemImage: sourceIcon)
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color(.tertiarySystemGroupedBackground), in: Capsule())
    }

    private var sourceIcon: String {
        switch item.sourceType {
        case .voice: return "mic.fill"
        case .image: return "photo.fill"
        case .mixed: return "square.grid.2x2.fill"
        default: return "keyboard"
        }
    }

    private func statusBadge(_ label: String, systemImage: String, tint: Color) -> some View {
        Label(label, systemImage: systemImage)
            .font(.caption.weight(.medium))
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(tint.opacity(0.12), in: Capsule())
    }

    // MARK: - Meta Section (Kategorie + Priorität)

    private var metaSection: some View {
        detailCard {
            if isEditing {
                VStack(spacing: 12) {
                    CategoryPickerView(selectionRawValue: categoryRawValueBinding, categories: categories)
                    Divider()
                    PriorityPickerView(selection: priorityBinding)
                }
            } else {
                HStack(spacing: 12) {
                    // Kategorie
                    if let category = MemoCategoryItem.item(for: item.categoryRawValue, in: categories) {
                        metaChip(
                            label: category.displayName,
                            systemImage: category.systemImage,
                            tint: category.tint
                        )
                    } else {
                        metaChip(label: "Keine Kategorie", systemImage: "tray", tint: .secondary)
                    }

                    Spacer()

                    // Priorität
                    metaChip(
                        label: item.priority.displayName,
                        systemImage: item.priority.systemImage,
                        tint: item.priority.tint
                    )
                }
            }
        }
    }

    private func metaChip(label: String, systemImage: String, tint: Color) -> some View {
        Label(label, systemImage: systemImage)
            .font(.subheadline.weight(.medium))
            .foregroundStyle(tint)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(tint.opacity(0.12), in: Capsule())
    }

    // MARK: - Reminder Section

    private var reminderSection: some View {
        detailCard {
            VStack(alignment: .leading, spacing: 12) {
                // Erledigt-Toggle immer sichtbar
                Toggle(isOn: completedBinding) {
                    Label("Erledigt", systemImage: item.isCompleted ? "checkmark.circle.fill" : "circle")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(item.isCompleted ? .green : .primary)
                }
                .tint(.green)

                Divider()

                if isEditing {
                    // Bearbeitungsmodus: Erinnerung ein/aus + DatePicker
                    Toggle(isOn: reminderEnabledBinding) {
                        Label("Erinnerung", systemImage: "bell")
                            .font(.subheadline.weight(.medium))
                    }
                    .tint(.accentColor)

                    if item.hasReminder {
                        DatePicker(
                            "Datum und Uhrzeit",
                            selection: reminderDateBinding,
                            in: Date()...,
                            displayedComponents: [.date, .hourAndMinute]
                        )
                        .font(.subheadline)
                    }
                } else if item.hasReminder, let reminderDate = item.reminderDate {
                    // Ansichtsmodus: Erinnerung aktiv
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Label("Erinnerung aktiv", systemImage: "bell.fill")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.green)

                            Text(reminderDate.germanFormatted(date: .complete, time: .shortened))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)

                            // Wiederholung anzeigen falls vorhanden
                            if reminderDate > Date() {
                                let diff = reminderDate.timeIntervalSinceNow
                                Text(relativeTimeLabel(diff))
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        Spacer()
                        Image(systemName: "bell.fill")
                            .font(.title2)
                            .foregroundStyle(.green.opacity(0.3))
                    }

                    // Snooze-Buttons (neu — fehlten im Original)
                    if !item.isCompleted {
                        HStack(spacing: 8) {
                            snoozeButton(label: "10 Min.", seconds: 600)
                            snoozeButton(label: "1 Std.", seconds: 3600)
                            snoozeButton(label: "Morgen", seconds: nextMorningOffset())
                        }
                    }
                } else {
                    // Keine Erinnerung
                    Label("Keine Erinnerung gesetzt", systemImage: "bell.slash")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func relativeTimeLabel(_ interval: TimeInterval) -> String {
        if interval < 3600 {
            let mins = Int(interval / 60)
            return "in \(mins) Minute\(mins == 1 ? "" : "n")"
        } else if interval < 86400 {
            let hours = Int(interval / 3600)
            return "in \(hours) Stunde\(hours == 1 ? "" : "n")"
        } else {
            let days = Int(interval / 86400)
            return "in \(days) Tag\(days == 1 ? "" : "en")"
        }
    }

    private func nextMorningOffset() -> TimeInterval {
        let calendar = Calendar.current
        let startOfTomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: Date()))
        let tomorrowMorning = startOfTomorrow.flatMap {
            calendar.date(bySettingHour: 9, minute: 0, second: 0, of: $0)
        } ?? Date().addingTimeInterval(86_400)

        return tomorrowMorning.timeIntervalSinceNow
    }

    private func snoozeButton(label: String, seconds: TimeInterval) -> some View {
        Button {
            snoozeReminder(by: seconds)
        } label: {
            Text(label)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.accentColor)
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(Color.accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func snoozeReminder(by seconds: TimeInterval) {
        let newDate = Date().addingTimeInterval(seconds)
        item.reminderDate = newDate
        item.hasReminder = true
        item.updatedAt = Date()

        Task { @MainActor in
            do {
                try await NotificationService.shared.scheduleReminder(for: item)
                try await syncCalendarEventIfNeeded()
                try modelContext.save()
                MemoWidgetSnapshotUpdater.refresh(in: modelContext)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    // MARK: - Text Section

    private var textSection: some View {
        VStack(spacing: 10) {
            // Notiztext
            if isEditing || !item.bodyText.trimmed.isEmpty {
                detailCard {
                    VStack(alignment: .leading, spacing: 8) {
                        sectionLabel("Notiz")
                        if isEditing {
                            TextEditor(text: $item.bodyText)
                                .frame(minHeight: 100)
                                .padding(8)
                                .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        } else {
                            Text(item.bodyText.trimmed.isEmpty ? "Kein Text" : item.bodyText)
                                .font(.body)
                                .foregroundStyle(item.bodyText.trimmed.isEmpty ? .secondary : .primary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                        }
                    }
                }
            }

            // Erkannter Bildtext — bereinigt, ohne "--- Bild 1 ---" Header
            if !item.recognizedText.trimmed.isEmpty {
                detailCard {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            sectionLabel("Erkannter Text")
                            Spacer()
                            Image(systemName: "text.viewfinder")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        if isEditing {
                            TextEditor(text: $item.recognizedText)
                                .frame(minHeight: 100)
                                .padding(8)
                                .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        } else {
                            // Fix: "--- Bild N ---" Header aus erkanntem Text entfernen
                            Text(cleanedRecognizedText)
                                .font(.body)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                        }
                    }
                }
            }
        }
    }

    /// Entfernt die "--- Bild N ---" Trennzeilen aus dem erkannten Text für saubere Darstellung
    private var cleanedRecognizedText: String {
        item.recognizedText
            .components(separatedBy: "\n")
            .filter { !$0.matches(pattern: "^--- Bild \\d+ ---$") }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Images Section

    @ViewBuilder
    private var imagesSection: some View {
        if !item.imageFileNames.isEmpty {
            detailCard {
                VStack(alignment: .leading, spacing: 10) {
                    sectionLabel("Bilder")
                    LazyVGrid(
                        columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)],
                        spacing: 10
                    ) {
                        ForEach(item.imageFileNames, id: \.self) { fileName in
                            if let image = loadedThumbnails[fileName] {
                                Button {
                                    presentFullImage(fileName: fileName)
                                } label: {
                                    Image(uiImage: image)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(height: 140)
                                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                        .overlay {
                                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                                .strokeBorder(Color.primary.opacity(0.08))
                                        }
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Bild öffnen")
                            } else if didLoadThumbnails {
                                imagePlaceholder {
                                    Label("Nicht gefunden", systemImage: "photo.badge.exclamationmark")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            } else {
                                imagePlaceholder {
                                    ProgressView()
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Detected Info Section

    @ViewBuilder
    private var detectedSection: some View {
        let hasAny = !item.detectedPhoneNumbers.isEmpty
            || !item.detectedURLs.isEmpty
            || !item.detectedAddresses.isEmpty
            || !item.detectedDateStrings.isEmpty

        if hasAny {
            detailCard {
                VStack(alignment: .leading, spacing: 14) {
                    sectionLabel("Erkannte Informationen")

                    if !item.detectedPhoneNumbers.isEmpty {
                        detectedGroup(
                            title: "Telefon",
                            systemImage: "phone.fill",
                            tint: .green,
                            values: item.detectedPhoneNumbers
                        ) { openPhone($0) }
                    }

                    if !item.detectedURLs.isEmpty {
                        if !item.detectedPhoneNumbers.isEmpty { Divider() }
                        detectedGroup(
                            title: "Links",
                            systemImage: "link",
                            tint: .accentColor,
                            values: item.detectedURLs
                        ) { value in
                            if let url = webURL(from: value) { openURL(url) }
                            else { errorMessage = "Dieser Link kann nicht geöffnet werden." }
                        }
                    }

                    if !item.detectedAddresses.isEmpty {
                        if !item.detectedPhoneNumbers.isEmpty || !item.detectedURLs.isEmpty { Divider() }
                        detectedGroup(
                            title: "Adressen",
                            systemImage: "mappin.circle.fill",
                            tint: .orange,
                            values: item.detectedAddresses,
                            action: nil
                        )
                    }

                    if !item.detectedDateStrings.isEmpty {
                        if !item.detectedPhoneNumbers.isEmpty || !item.detectedURLs.isEmpty || !item.detectedAddresses.isEmpty { Divider() }
                        detectedGroup(
                            title: "Erkannte Termine",
                            systemImage: "calendar",
                            tint: .purple,
                            values: item.detectedDateStrings,
                            action: nil
                        )
                    }
                }
            }
        }
    }

    private func detectedGroup(
        title: String,
        systemImage: String,
        tint: Color,
        values: [String],
        action: ((String) -> Void)?
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(tint)

            ForEach(values, id: \.self) { value in
                if let action {
                    Button {
                        action(value)
                    } label: {
                        HStack {
                            Text(value)
                                .font(.subheadline)
                                .foregroundStyle(tint)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .lineLimit(1)
                            Image(systemName: "arrow.up.right")
                                .font(.caption)
                                .foregroundStyle(tint.opacity(0.6))
                        }
                        .padding(10)
                        .background(tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .buttonStyle(.plain)
                } else {
                    Text(value)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .padding(10)
                        .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }
        }
    }

    // MARK: - Action Section

    private var actionSection: some View {
        VStack(spacing: 10) {
            // Erinnerung entfernen
            if item.hasReminder {
                Button { removeReminder() } label: {
                    Label("Erinnerung entfernen", systemImage: "bell.slash")
                        .font(.subheadline.weight(.medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .foregroundStyle(.accentColor)
                        .background(Color.accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
            }

            // Als erledigt markieren / Erledigt-Status
            if item.isCompleted {
                Button {
                    // Wieder öffnen
                    item.isCompleted = false
                    item.updatedAt = Date()
                    Task { @MainActor in
                        do {
                            if item.hasReminder {
                                try await NotificationService.shared.scheduleReminder(for: item)
                            }
                            try modelContext.save()
                            MemoWidgetSnapshotUpdater.refresh(in: modelContext)
                        } catch {
                            errorMessage = error.localizedDescription
                        }
                    }
                } label: {
                    Label("Als offen markieren", systemImage: "arrow.uturn.left.circle")
                        .font(.subheadline.weight(.medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .foregroundStyle(.secondary)
                        .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
            } else {
                Button { markCompleted() } label: {
                    Label("Als erledigt markieren", systemImage: "checkmark.circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .foregroundStyle(.white)
                        .background(Color.green, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
            }

            // Löschen
            Button(role: .destructive) {
                showDeleteConfirmation = true
            } label: {
                Label("Löschen", systemImage: "trash")
                    .font(.subheadline.weight(.medium))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .foregroundStyle(.red)
                    .background(Color.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Memo löschen")
        }
    }

    // MARK: - Reusable Layout Helpers

    private func detailCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(14)
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

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .tracking(0.4)
    }

    // MARK: - Bindings

    private var categoryRawValueBinding: Binding<String?> {
        Binding(
            get: { item.categoryRawValue },
            set: { item.categoryRawValue = $0; item.updatedAt = Date() }
        )
    }

    private var priorityBinding: Binding<MemoPriority> {
        Binding(
            get: { item.priority },
            set: { item.priority = $0; item.updatedAt = Date() }
        )
    }

    private var reminderEnabledBinding: Binding<Bool> {
        Binding(
            get: { item.hasReminder },
            set: { isEnabled in
                item.hasReminder = isEnabled
                item.updatedAt = Date()
                if isEnabled, item.reminderDate == nil {
                    item.reminderDate = Date().addingTimeInterval(3_600)
                }
            }
        )
    }

    private var reminderDateBinding: Binding<Date> {
        Binding(
            get: { item.reminderDate ?? Date().addingTimeInterval(3_600) },
            set: { item.reminderDate = $0; item.hasReminder = true; item.updatedAt = Date() }
        )
    }

    private var completedBinding: Binding<Bool> {
        Binding(
            get: { item.isCompleted },
            set: { newValue in
                item.isCompleted = newValue
                item.updatedAt = Date()
                handleCompletionNotification()
            }
        )
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )
    }

    // MARK: - Actions

    private func saveChanges() {
        if item.title.trimmed.isEmpty { item.title = "Ohne Titel" }
        item.updatedAt = Date()
        updateDetectedInfo()

        Task { @MainActor in
            do {
                if item.isCompleted || !item.hasReminder {
                    NotificationService.shared.cancelReminder(for: item)
                    await removeCalendarEvent()
                } else {
                    try await NotificationService.shared.scheduleReminder(for: item)
                    try await syncCalendarEventIfNeeded()
                }
                try modelContext.save()
                MemoWidgetSnapshotUpdater.refresh(in: modelContext)
                isEditing = false
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func removeReminder() {
        item.hasReminder = false
        item.reminderDate = nil
        item.updatedAt = Date()
        NotificationService.shared.cancelReminder(for: item)

        Task { @MainActor in
            await removeCalendarEvent()
            do {
                try modelContext.save()
                MemoWidgetSnapshotUpdater.refresh(in: modelContext)
            }
            catch { errorMessage = error.localizedDescription }
        }
    }

    private func markCompleted() {
        item.isCompleted = true
        item.updatedAt = Date()
        NotificationService.shared.cancelReminder(for: item)

        Task { @MainActor in
            await removeCalendarEvent()
            do {
                try modelContext.save()
                MemoWidgetSnapshotUpdater.refresh(in: modelContext)
            }
            catch { errorMessage = error.localizedDescription }
        }
    }

    private func handleCompletionNotification() {
        Task { @MainActor in
            if item.isCompleted {
                NotificationService.shared.cancelReminder(for: item)
                await removeCalendarEvent()
            } else if item.hasReminder {
                do { try await NotificationService.shared.scheduleReminder(for: item) }
                catch { errorMessage = error.localizedDescription }
            }
            do { try modelContext.save() }
            catch { errorMessage = error.localizedDescription }
            MemoWidgetSnapshotUpdater.refresh(in: modelContext)
        }
    }

    private func deleteMemo() {
        Task { @MainActor in
            NotificationService.shared.cancelReminder(for: item)
            await removeCalendarEvent()
            imageStorage.deleteImages(fileNames: item.imageFileNames)
            modelContext.delete(item)
            do {
                try modelContext.save()
                MemoWidgetSnapshotUpdater.refresh(in: modelContext)
                dismiss()
            }
            catch { errorMessage = error.localizedDescription }
        }
    }

    /// Überträgt ein geändertes Erinnerungsdatum (Bearbeiten, Snooze) auf den
    /// bereits synchronisierten Kalendertermin, damit Kalender und App nicht auseinanderlaufen.
    private func syncCalendarEventIfNeeded() async throws {
        guard item.syncsToCalendar, item.calendarEventIdentifier != nil else { return }
        item.calendarEventIdentifier = try await CalendarSyncService.shared.saveEvent(for: item)
    }

    /// Löscht den synchronisierten Kalendertermin, damit dessen Alarme und
    /// Wiederholungen nicht weiterlaufen, wenn die Erinnerung beendet wurde.
    private func removeCalendarEvent() async {
        guard let eventIdentifier = item.calendarEventIdentifier else { return }
        try? await CalendarSyncService.shared.deleteEvent(with: eventIdentifier)
        item.calendarEventIdentifier = nil
        item.syncsToCalendar = false
    }

    private func openPhone(_ phoneNumber: String) {
        let digits = phoneNumber.filter { $0.isNumber || $0 == "+" }
        if let url = URL(string: "tel://\(digits)") { openURL(url) }
        else { errorMessage = "Diese Telefonnummer kann nicht geöffnet werden." }
    }

    private func webURL(from value: String) -> URL? {
        let v = value.trimmed
        guard !v.isEmpty else { return nil }
        if let url = URL(string: v), url.scheme != nil { return url }
        return URL(string: "https://\(v)")
    }

    private func updateDetectedInfo() {
        let info = DataDetectionService.shared.detect(
            in: [item.bodyText, item.recognizedText].joined(separator: "\n")
        )
        item.detectedPhoneNumbers = info.phoneNumbers
        item.detectedURLs = info.urls
        item.detectedAddresses = info.addresses
        item.detectedDateStrings = info.formattedDates()
    }

    private func imagePlaceholder<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(Color(.tertiarySystemGroupedBackground))
            .frame(height: 140)
            .overlay { content() }
    }

    /// Dekodiert die Bilder abseits des Main Threads als Thumbnails —
    /// der synchrone Volldecode im View-Body ruckelte bei jedem Re-Render.
    private func loadThumbnails() async {
        let fileNames = item.imageFileNames
        guard !fileNames.isEmpty else {
            loadedThumbnails = [:]
            didLoadThumbnails = true
            return
        }

        let storage = imageStorage
        let thumbnails = await Task.detached(priority: .userInitiated) {
            var result: [String: UIImage] = [:]
            for fileName in fileNames {
                result[fileName] = storage.loadThumbnail(fileName: fileName, maxPixelDimension: 700)
            }
            return result
        }.value

        loadedThumbnails = thumbnails
        didLoadThumbnails = true
    }

    private func presentFullImage(fileName: String) {
        Task {
            let storage = imageStorage
            let image = await Task.detached(priority: .userInitiated) {
                storage.loadImage(fileName: fileName)
            }.value

            if let image {
                selectedImage = DetailImage(fileName: fileName, image: image)
            } else {
                errorMessage = "Das Bild konnte nicht geladen werden."
            }
        }
    }

    private func imageDetailView(_ detailImage: DetailImage) -> some View {
        ScrollView {
            Image(uiImage: detailImage.image)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity)
                .padding()
        }
        .background(Color(.systemBackground))
    }
}

// MARK: - String Helper Extension

private extension String {
    func matches(pattern: String) -> Bool {
        (try? NSRegularExpression(pattern: pattern))
            .map { $0.firstMatch(in: self, range: NSRange(self.startIndex..., in: self)) != nil }
        ?? false
    }
}
