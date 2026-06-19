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
    @Query(sort: \MemoCategoryItem.sortOrder) private var categories: [MemoCategoryItem]

    @Bindable var item: MemoItem

    @State private var isEditing = false
    @State private var errorMessage: String?
    @State private var selectedImage: DetailImage?
    @State private var showDeleteConfirmation = false

    private let imageStorage = ImageStorageService.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                titleSection
                organizationSection
                reminderSection
                textSection
                imagesSection
                detectedSection
                actionSection
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Details")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(isEditing ? "Sichern" : "Bearbeiten") {
                    isEditing ? saveChanges() : (isEditing = true)
                }
            }
        }
        .alert("Hinweis", isPresented: errorBinding) {
            Button("OK", role: .cancel) {
                errorMessage = nil
            }
        } message: {
            Text(errorMessage ?? "")
        }
        .confirmationDialog("Memo wirklich löschen?", isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
            Button("Löschen", role: .destructive) {
                deleteMemo()
            }
            Button("Abbrechen", role: .cancel) {}
        }
        .sheet(item: $selectedImage) { detailImage in
            NavigationStack {
                imageDetailView(detailImage)
                    .navigationTitle("Bild")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Schließen") {
                                selectedImage = nil
                            }
                        }
                    }
            }
        }
    }

    private var titleSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            if isEditing {
                TextField("Titel", text: $item.title)
                    .font(.title2.weight(.semibold))
                    .textFieldStyle(.roundedBorder)
            } else {
                Text(item.title)
                    .font(.title2.weight(.semibold))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Label(item.sourceType.displayName, systemImage: "square.and.pencil")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var organizationSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 14) {
                if isEditing {
                    CategoryPickerView(selectionRawValue: categoryRawValueBinding, categories: categories)
                    PriorityPickerView(selection: priorityBinding)
                } else {
                    HStack {
                        if let category = MemoCategoryItem.item(for: item.categoryRawValue, in: categories) {
                            Label(category.displayName, systemImage: category.systemImage)
                                .foregroundStyle(category.tint)
                        } else {
                            Label("Keine Kategorie", systemImage: "tray")
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Label(item.priority.displayName, systemImage: item.priority.systemImage)
                            .foregroundStyle(item.priority.tint)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var reminderSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                Toggle("Erledigt", isOn: completedBinding)

                if isEditing {
                    Toggle("Erinnerung", isOn: reminderEnabledBinding)

                    if item.hasReminder {
                        DatePicker(
                            "Termin",
                            selection: reminderDateBinding,
                            in: Date()...,
                            displayedComponents: [.date, .hourAndMinute]
                        )

                        Picker("Wiederholen", selection: reminderRepeatBinding) {
                            ForEach(MemoReminderRepeatRule.allCases) { repeatRule in
                                Label(repeatRule.displayName, systemImage: repeatRule.systemImage)
                                    .tag(repeatRule)
                            }
                        }

                        Picker("Vorher erinnern", selection: reminderLeadTimeBinding) {
                            ForEach(MemoReminderLeadTime.allCases) { leadTime in
                                Label(leadTime.displayName, systemImage: leadTime.systemImage)
                                    .tag(leadTime)
                            }
                        }

                        Toggle("Mit iOS-Kalender synchronisieren", isOn: calendarSyncBinding)
                    }
                } else if item.hasReminder, let reminderDate = item.reminderDate {
                    Label("Erinnerung aktiv", systemImage: "bell.fill")
                        .foregroundStyle(.green)

                    Text(reminderDate.formatted(date: .abbreviated, time: .shortened))
                        .foregroundStyle(.secondary)

                    Label(item.reminderRepeatRule.displayName, systemImage: item.reminderRepeatRule.systemImage)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    if item.reminderLeadTime.hasLeadNotification {
                        Label(item.reminderLeadTime.shortDisplayName, systemImage: item.reminderLeadTime.systemImage)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    if item.syncsToCalendar {
                        Label("Mit iOS-Kalender synchronisiert", systemImage: "calendar.badge.checkmark")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Label("Keine Erinnerung", systemImage: "bell.slash")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var textSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            editableTextBlock(title: "Notiztext", text: $item.bodyText)

            if isEditing || !item.recognizedText.trimmed.isEmpty {
                editableTextBlock(title: "Erkannter Bildtext", text: $item.recognizedText)
            }
        }
    }

    @ViewBuilder
    private var imagesSection: some View {
        if !item.imageFileNames.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("Bilder")
                    .font(.headline)

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 12)], spacing: 12) {
                    ForEach(item.imageFileNames, id: \.self) { fileName in
                        if let image = imageStorage.loadImage(fileName: fileName) {
                            Button {
                                selectedImage = DetailImage(fileName: fileName, image: image)
                            } label: {
                                Image(uiImage: image)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(height: 150)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Bild öffnen")
                        } else {
                            Label("Bilddatei nicht gefunden", systemImage: "photo.badge.exclamationmark")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    private var detectedSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            if !item.detectedPhoneNumbers.isEmpty {
                detectedValues(title: "Telefonnummern", systemImage: "phone", values: item.detectedPhoneNumbers) { value in
                    openPhone(value)
                }
            }

            if !item.detectedURLs.isEmpty {
                detectedValues(title: "Links", systemImage: "link", values: item.detectedURLs) { value in
                    if let url = webURL(from: value) {
                        openURL(url)
                    } else {
                        errorMessage = "Dieser Link kann nicht geöffnet werden."
                    }
                }
            }

            if !item.detectedAddresses.isEmpty {
                detectedValues(title: "Adressen", systemImage: "mappin.and.ellipse", values: item.detectedAddresses, action: nil)
            }

            if !item.detectedDateStrings.isEmpty {
                detectedValues(title: "Erkannte Termine", systemImage: "calendar", values: item.detectedDateStrings, action: nil)
            }
        }
    }

    private var actionSection: some View {
        VStack(spacing: 12) {
            if item.hasReminder {
                if !item.isCompleted {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Erinnerung verschieben", systemImage: "clock.arrow.circlepath")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        HStack {
                            Button("10 Min.") {
                                snoozeReminder(by: 10 * 60)
                            }

                            Button("1 Std.") {
                                snoozeReminder(by: 60 * 60)
                            }

                            Button("Morgen") {
                                snoozeReminderUntilTomorrow()
                            }
                        }
                        .buttonStyle(.bordered)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                Button {
                    removeReminder()
                } label: {
                    Label("Erinnerung entfernen", systemImage: "bell.slash")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }

            if item.isCompleted {
                Label("Erledigt", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .frame(maxWidth: .infinity)
            } else {
                Button {
                    markCompleted()
                } label: {
                    Label("Als erledigt markieren", systemImage: "checkmark.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }

            Button(role: .destructive) {
                showDeleteConfirmation = true
            } label: {
                Label("Löschen", systemImage: "trash")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .accessibilityLabel("Memo löschen")
        }
    }

    private var categoryRawValueBinding: Binding<String?> {
        Binding(
            get: { item.categoryRawValue },
            set: {
                item.categoryRawValue = $0
                item.updatedAt = Date()
            }
        )
    }

    private var priorityBinding: Binding<MemoPriority> {
        Binding(
            get: { item.priority },
            set: {
                item.priority = $0
                item.updatedAt = Date()
            }
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

                if !isEnabled {
                    item.reminderRepeatRule = .none
                    item.reminderLeadTime = .none
                    item.syncsToCalendar = false
                }
            }
        )
    }

    private var reminderDateBinding: Binding<Date> {
        Binding(
            get: { item.reminderDate ?? Date().addingTimeInterval(3_600) },
            set: {
                item.reminderDate = $0
                item.hasReminder = true
                item.updatedAt = Date()
            }
        )
    }

    private var reminderRepeatBinding: Binding<MemoReminderRepeatRule> {
        Binding(
            get: { item.reminderRepeatRule },
            set: {
                item.reminderRepeatRule = $0
                item.updatedAt = Date()
            }
        )
    }

    private var reminderLeadTimeBinding: Binding<MemoReminderLeadTime> {
        Binding(
            get: { item.reminderLeadTime },
            set: {
                item.reminderLeadTime = $0
                item.updatedAt = Date()
            }
        )
    }

    private var calendarSyncBinding: Binding<Bool> {
        Binding(
            get: { item.syncsToCalendar },
            set: {
                item.syncsToCalendar = $0
                item.updatedAt = Date()
            }
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

    private func editableTextBlock(title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)

            if isEditing {
                TextEditor(text: text)
                    .frame(minHeight: 110)
                    .padding(8)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
            } else if !text.wrappedValue.trimmed.isEmpty {
                Text(text.wrappedValue)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            } else {
                Text("Kein Text")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func detectedValues(
        title: String,
        systemImage: String,
        values: [String],
        action: ((String) -> Void)?
    ) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                Label(title, systemImage: systemImage)
                    .font(.headline)

                ForEach(values, id: \.self) { value in
                    if let action {
                        Button {
                            action(value)
                        } label: {
                            Text(value)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    } else {
                        Text(value)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
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

    private func saveChanges() {
        if item.title.trimmed.isEmpty {
            item.title = "Ohne Titel"
        }

        item.updatedAt = Date()
        updateDetectedInfo()

        Task { @MainActor in
            do {
                if item.isCompleted || !item.hasReminder {
                    NotificationService.shared.cancelReminder(for: item)
                    await removeCalendarEventIfNeeded()
                } else {
                    try await NotificationService.shared.scheduleReminder(for: item)
                    try await syncCalendarEventIfNeeded()
                }

                try modelContext.save()
                refreshWidgetSnapshot()
                isEditing = false
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func removeReminder() {
        item.hasReminder = false
        item.reminderDate = nil
        item.reminderRepeatRule = .none
        item.reminderLeadTime = .none
        item.syncsToCalendar = false
        let calendarEventIdentifier = item.calendarEventIdentifier
        item.calendarEventIdentifier = nil
        item.updatedAt = Date()
        NotificationService.shared.cancelReminder(for: item)

        Task { @MainActor in
            do {
                try? await CalendarSyncService.shared.deleteEvent(with: calendarEventIdentifier)
                try modelContext.save()
                refreshWidgetSnapshot()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func markCompleted() {
        item.isCompleted = true
        item.syncsToCalendar = false
        let calendarEventIdentifier = item.calendarEventIdentifier
        item.calendarEventIdentifier = nil
        item.updatedAt = Date()
        NotificationService.shared.cancelReminder(for: item)

        Task { @MainActor in
            do {
                try? await CalendarSyncService.shared.deleteEvent(with: calendarEventIdentifier)
                try modelContext.save()
                refreshWidgetSnapshot()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func snoozeReminder(by timeInterval: TimeInterval) {
        postponeReminder(to: Date().addingTimeInterval(timeInterval))
    }

    private func snoozeReminderUntilTomorrow() {
        let calendar = Calendar.current
        let sourceDate = item.reminderDate ?? Date().addingTimeInterval(3_600)
        let reminderTime = calendar.dateComponents([.hour, .minute], from: sourceDate)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: Date()) ?? Date().addingTimeInterval(86_400)
        var targetComponents = calendar.dateComponents([.year, .month, .day], from: tomorrow)
        targetComponents.hour = reminderTime.hour
        targetComponents.minute = reminderTime.minute

        postponeReminder(to: calendar.date(from: targetComponents) ?? tomorrow)
    }

    private func postponeReminder(to date: Date) {
        let previousDate = item.reminderDate
        let previousRepeatRule = item.reminderRepeatRule
        let previousLeadTime = item.reminderLeadTime

        item.hasReminder = true
        item.isCompleted = false
        item.reminderDate = max(date, Date().addingTimeInterval(60))
        item.reminderRepeatRule = .none
        item.reminderLeadTime = .none
        item.updatedAt = Date()

        Task { @MainActor in
            do {
                try await NotificationService.shared.scheduleReminder(for: item)
                try await syncCalendarEventIfNeeded()
                try modelContext.save()
                refreshWidgetSnapshot()

                if previousRepeatRule.isRepeating {
                    errorMessage = "Erinnerung wurde einmalig verschoben. Die Wiederholung wurde dafür deaktiviert."
                }
            } catch {
                item.reminderDate = previousDate
                item.reminderRepeatRule = previousRepeatRule
                item.reminderLeadTime = previousLeadTime
                item.updatedAt = Date()
                errorMessage = error.localizedDescription
            }
        }
    }

    private func handleCompletionNotification() {
        Task { @MainActor in
            if item.isCompleted {
                NotificationService.shared.cancelReminder(for: item)
                await removeCalendarEventIfNeeded()
            } else if item.hasReminder {
                do {
                    try await NotificationService.shared.scheduleReminder(for: item)
                    try await syncCalendarEventIfNeeded()
                } catch {
                    errorMessage = error.localizedDescription
                }
            }

            try? modelContext.save()
            refreshWidgetSnapshot()
        }
    }

    private func deleteMemo() {
        Task { @MainActor in
            NotificationService.shared.cancelReminder(for: item)
            try? await CalendarSyncService.shared.deleteEvent(with: item.calendarEventIdentifier)
            imageStorage.deleteImages(fileNames: item.imageFileNames)
            modelContext.delete(item)

            do {
                try modelContext.save()
                refreshWidgetSnapshot()
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func openPhone(_ phoneNumber: String) {
        let digits = phoneNumber.filter { $0.isNumber || $0 == "+" }
        if let url = URL(string: "tel://\(digits)") {
            openURL(url)
        } else {
            errorMessage = "Diese Telefonnummer kann nicht geöffnet werden."
        }
    }

    private func webURL(from value: String) -> URL? {
        let trimmedValue = value.trimmed
        guard !trimmedValue.isEmpty else {
            return nil
        }

        if let url = URL(string: trimmedValue), url.scheme != nil {
            return url
        }

        return URL(string: "https://\(trimmedValue)")
    }

    private func updateDetectedInfo() {
        let info = DataDetectionService.shared.detect(in: [item.bodyText, item.recognizedText].joined(separator: "\n"))
        item.detectedPhoneNumbers = info.phoneNumbers
        item.detectedURLs = info.urls
        item.detectedAddresses = info.addresses
        item.detectedDateStrings = info.formattedDates()
    }

    private func syncCalendarEventIfNeeded() async throws {
        guard item.syncsToCalendar,
              item.hasReminder,
              !item.isCompleted else {
            await removeCalendarEventIfNeeded()
            return
        }

        let calendarEventIdentifier = try await CalendarSyncService.shared.saveEvent(for: item)
        item.calendarEventIdentifier = calendarEventIdentifier
    }

    private func removeCalendarEventIfNeeded() async {
        let calendarEventIdentifier = item.calendarEventIdentifier
        item.calendarEventIdentifier = nil
        item.syncsToCalendar = false
        try? await CalendarSyncService.shared.deleteEvent(with: calendarEventIdentifier)
    }

    private func refreshWidgetSnapshot() {
        let descriptor = FetchDescriptor<MemoItem>()
        if let items = try? modelContext.fetch(descriptor) {
            MemoWidgetSnapshotUpdater.update(from: items)
        }
    }
}
