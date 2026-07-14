import PhotosUI
import SwiftData
import SwiftUI
import UIKit

struct PreviewView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \MemoCategoryItem.sortOrder) private var categories: [MemoCategoryItem]

    @StateObject private var viewModel: PreviewViewModel
    @State private var selectedPhotoItems: [PhotosPickerItem] = []
    @State private var cameraSheet: CameraSheet?
    @State private var showDiscardConfirmation = false

    let onSave: () -> Void
    let onDiscard: () -> Void

    init(viewModel: PreviewViewModel, onSave: @escaping () -> Void, onDiscard: @escaping () -> Void) {
        _viewModel = StateObject(wrappedValue: viewModel)
        self.onSave = onSave
        self.onDiscard = onDiscard
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                heroCard
                contentCard
                reminderCard
                detectedInfoCard
                organizationCard
                actionCard
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .padding(.bottom, 32)
        }
        .background(Color(.systemGroupedBackground))
        .scrollDismissesKeyboard(.interactively)
        .onChange(of: selectedPhotoItems) { _, newItems in
            Task { await loadSelectedPhotos(newItems) }
        }
        .onChange(of: viewModel.bodyText) { _, _ in viewModel.textContentDidChange() }
        .onChange(of: viewModel.recognizedText) { _, _ in viewModel.textContentDidChange() }
        .task {
            await viewModel.refreshNotificationStatus()
            await viewModel.prepareInitialImagesIfNeeded()
        }
        .sheet(item: $cameraSheet) { _ in
            CameraPickerView { image in
                Task { await viewModel.addImage(image) }
            }
        }
        .confirmationDialog("Entwurf verwerfen?", isPresented: $showDiscardConfirmation, titleVisibility: .visible) {
            Button("Verwerfen", role: .destructive) {
                viewModel.discardTemporaryImages()
                onDiscard()
            }
            Button("Abbrechen", role: .cancel) {}
        }
        .alert("Hinweis", isPresented: errorBinding) {
            Button("OK", role: .cancel) { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }

    // MARK: - Hero Card

    private var heroCard: some View {
        HStack(spacing: 14) {
            Image(systemName: viewModel.hasReminder ? "bell.badge.fill" : "doc.text.fill")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 48, height: 48)
                .background(
                    Color.accentColor.gradient,
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                )

            VStack(alignment: .leading, spacing: 3) {
                Text(viewModel.hasReminder ? "Neue Erinnerung" : "Neue Notiz")
                    .font(.title3.weight(.bold))

                HStack(spacing: 6) {
                    Circle()
                        .fill(viewModel.canSave ? Color.green : Color.orange)
                        .frame(width: 7, height: 7)
                    Text(viewModel.canSave ? "Bereit zum Speichern" : "Noch unvollständig")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()
        }
        .detailCard()
    }

    // MARK: - Content Card

    private var contentCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionLabel("Inhalt")

            // Titel
            VStack(alignment: .leading, spacing: 6) {
                Text("Titel")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                TextField("Titel eingeben", text: $viewModel.title)
                    .font(.headline)
                    .padding(12)
                    .background(
                        Color(.tertiarySystemGroupedBackground),
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                    )
            }

            // Notiztext
            VStack(alignment: .leading, spacing: 6) {
                Text("Notiztext")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                TextEditor(text: $viewModel.bodyText)
                    .frame(minHeight: 100)
                    .padding(10)
                    .scrollContentBackground(.hidden)
                    .background(
                        Color(.tertiarySystemGroupedBackground),
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                    )
            }

            // Erkannter Text (nur wenn vorhanden)
            if !viewModel.recognizedText.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Erkannter Text")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Image(systemName: "text.viewfinder")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    TextEditor(text: $viewModel.recognizedText)
                        .frame(minHeight: 90)
                        .padding(10)
                        .scrollContentBackground(.hidden)
                        .background(
                            Color(.tertiarySystemGroupedBackground),
                            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                        )
                }
            }

            // Bilder hinzufügen (inline in Content Card)
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Bilder")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    if !viewModel.imageAttachments.isEmpty {
                        Text("\(viewModel.imageAttachments.count)/3")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                // Bildvorschau
                if !viewModel.imageAttachments.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(viewModel.imageAttachments) { attachment in
                                ZStack(alignment: .topTrailing) {
                                    Image(uiImage: attachment.image)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 100, height: 100)
                                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                        .overlay {
                                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                                .strokeBorder(Color.primary.opacity(0.08))
                                        }

                                    Button {
                                        viewModel.removeImage(attachment)
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .font(.title3)
                                            .symbolRenderingMode(.palette)
                                            .foregroundStyle(.white, Color.black.opacity(0.6))
                                    }
                                    .buttonStyle(.plain)
                                    .padding(4)
                                    .accessibilityLabel("Bild entfernen")
                                }
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }

                // OCR Status
                ocrStatusView

                // Bild-Buttons
                if viewModel.canAddMoreImages {
                    HStack(spacing: 10) {
                        Button {
                            Task { await openCamera() }
                        } label: {
                            Label("Kamera", systemImage: "camera")
                                .font(.subheadline.weight(.medium))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                        }
                        .buttonStyle(.bordered)

                        PhotosPicker(
                            selection: $selectedPhotoItems,
                            maxSelectionCount: viewModel.remainingImageSlots,
                            matching: .images
                        ) {
                            Label("Galerie", systemImage: "photo")
                                .font(.subheadline.weight(.medium))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                        }
                        .buttonStyle(.bordered)
                    }
                } else {
                    Label("Maximal 3 Bilder erreicht", systemImage: "info.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if viewModel.isProcessingImage {
                    HStack(spacing: 8) {
                        ProgressView().scaleEffect(0.8)
                        Text("Bild wird vorbereitet …")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .detailCard()
    }

    // MARK: - Reminder Card

    private var reminderCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionLabel("Erinnerung")

            // Vorgeschlagenes Datum
            if let suggestedDate = viewModel.suggestedReminderDate, !viewModel.hasReminder {
                HStack(spacing: 12) {
                    Image(systemName: "calendar.badge.clock")
                        .font(.title3)
                        .foregroundStyle(.accentColor)
                        .frame(width: 36)

                    VStack(alignment: .leading, spacing: 3) {
                        Text("Erkannter Termin")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(suggestedDate.germanFormatted(date: .abbreviated, time: .shortened))
                            .font(.subheadline.weight(.medium))
                    }

                    Spacer()

                    Button {
                        viewModel.acceptSuggestedReminder()
                    } label: {
                        Text("Übernehmen")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.accentColor)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.accentColor.opacity(0.1), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
                .padding(12)
                .background(Color.accentColor.opacity(0.06), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.accentColor.opacity(0.2))
                }
            }

            // Toggle
            Toggle(isOn: $viewModel.hasReminder) {
                Label("Als Erinnerung speichern", systemImage: "bell")
                    .font(.subheadline.weight(.medium))
            }
            .tint(.accentColor)

            if viewModel.hasReminder {
                Divider()

                // DatePicker
                DatePicker(
                    "Datum und Uhrzeit",
                    selection: reminderDateBinding,
                    in: Date()...,
                    displayedComponents: [.date, .hourAndMinute]
                )
                .font(.subheadline)

                // Wiederholen
                Picker("Wiederholen", selection: $viewModel.reminderRepeatRule) {
                    ForEach(MemoReminderRepeatRule.allCases) { rule in
                        Label(rule.displayName, systemImage: rule.systemImage).tag(rule)
                    }
                }
                .font(.subheadline)

                // Vorab erinnern
                Picker("Vorab erinnern", selection: $viewModel.reminderLeadTime) {
                    ForEach(MemoReminderLeadTime.allCases) { leadTime in
                        Label(leadTime.displayName, systemImage: leadTime.systemImage).tag(leadTime)
                    }
                }
                .font(.subheadline)

                // Kalender
                Toggle(isOn: $viewModel.syncsToCalendar) {
                    Label("Mit iOS-Kalender synchronisieren", systemImage: "calendar")
                        .font(.subheadline)
                }
                .tint(.accentColor)

                if viewModel.syncsToCalendar {
                    Label("Ein Termin wird im iOS-Kalender erstellt und bei Änderungen aktualisiert.", systemImage: "calendar.badge.plus")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                // Validation
                if let msg = viewModel.reminderValidationMessage {
                    Label(msg, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }

                // Benachrichtigungs-Status
                Divider()

                HStack {
                    Label("Benachrichtigungen", systemImage: "bell")
                        .font(.subheadline)
                    Spacer()
                    Text(viewModel.notificationStatusText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if viewModel.shouldShowNotificationPermissionButton {
                    Button {
                        Task { await viewModel.requestNotificationAuthorization() }
                    } label: {
                        Label("Benachrichtigungen erlauben", systemImage: "bell.badge")
                            .font(.subheadline.weight(.medium))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .foregroundStyle(.accentColor)
                            .background(Color.accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .detailCard()
    }

    // MARK: - Detected Info Card

    @ViewBuilder
    private var detectedInfoCard: some View {
        if !viewModel.detectedInfo.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                sectionLabel("Erkannte Informationen")

                if !viewModel.detectedDateSuggestions.isEmpty {
                    detectedGroup(
                        title: "Erkannte Termine",
                        systemImage: "calendar",
                        tint: .purple
                    ) {
                        ForEach(viewModel.detectedDateSuggestions) { suggestion in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(suggestion.displayText)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                if suggestion.isFuture {
                                    Button {
                                        viewModel.useDetectedDate(suggestion.date)
                                    } label: {
                                        Label("Als Erinnerung verwenden", systemImage: "bell.badge")
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(.accentColor)
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 5)
                                            .background(Color.accentColor.opacity(0.1), in: Capsule())
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }

                if !viewModel.detectedInfo.phoneNumbers.isEmpty {
                    if !viewModel.detectedDateSuggestions.isEmpty { Divider() }
                    detectedGroup(title: "Telefon", systemImage: "phone.fill", tint: .green) {
                        ForEach(viewModel.detectedInfo.phoneNumbers, id: \.self) { number in
                            detectedRow(value: number, tint: .green)
                        }
                    }
                }

                if !viewModel.detectedInfo.urls.isEmpty {
                    Divider()
                    detectedGroup(title: "Links", systemImage: "link", tint: .accentColor) {
                        ForEach(viewModel.detectedInfo.urls, id: \.self) { url in
                            detectedRow(value: url, tint: .accentColor)
                        }
                    }
                }

                if !viewModel.detectedInfo.addresses.isEmpty {
                    Divider()
                    detectedGroup(title: "Adressen", systemImage: "mappin.circle.fill", tint: .orange) {
                        ForEach(viewModel.detectedInfo.addresses, id: \.self) { address in
                            Text(address)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                    }
                }
            }
            .detailCard()
        }
    }

    // MARK: - Organization Card

    private var organizationCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionLabel("Einordnung")
            CategoryPickerView(selectionRawValue: $viewModel.categoryRawValue, categories: categories)
            Divider()
            PriorityPickerView(selection: $viewModel.priority)
        }
        .detailCard()
    }

    // MARK: - Action Card

    private var actionCard: some View {
        VStack(spacing: 10) {
            // Primär: Speichern
            Button {
                save(forceNormalNote: false)
            } label: {
                HStack {
                    if viewModel.isSaving {
                        ProgressView().scaleEffect(0.8).tint(.white)
                    }
                    Label(
                        viewModel.hasReminder ? "Als Erinnerung speichern" : "Notiz speichern",
                        systemImage: viewModel.hasReminder ? "bell.fill" : "note.text"
                    )
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!viewModel.canSave)

            // Sekundär: Ohne Erinnerung speichern
            if viewModel.hasReminder {
                Button {
                    save(forceNormalNote: true)
                } label: {
                    Label("Ohne Erinnerung speichern", systemImage: "bell.slash")
                        .font(.subheadline.weight(.medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .foregroundStyle(.accentColor)
                        .background(
                            Color.accentColor.opacity(0.1),
                            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                        )
                }
                .buttonStyle(.plain)
                .disabled(!viewModel.canSave)
            }

            // Destruktiv: Verwerfen
            Button(role: .destructive) {
                showDiscardConfirmation = true
            } label: {
                Label("Verwerfen", systemImage: "trash")
                    .font(.subheadline.weight(.medium))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .foregroundStyle(.red)
                    .background(
                        Color.red.opacity(0.1),
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                    )
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Helpers

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .tracking(0.4)
    }

    private func detectedGroup<Content: View>(
        title: String,
        systemImage: String,
        tint: Color,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(tint)
            content()
        }
    }

    private func detectedRow(value: String, tint: Color) -> some View {
        HStack {
            Text(value)
                .font(.subheadline)
                .foregroundStyle(tint)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "arrow.up.right")
                .font(.caption)
                .foregroundStyle(tint.opacity(0.6))
        }
        .padding(10)
        .background(tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    @ViewBuilder
    private var ocrStatusView: some View {
        switch viewModel.ocrState {
        case .idle:
            EmptyView()
        case .processing:
            HStack(spacing: 8) {
                ProgressView().scaleEffect(0.8)
                Text("Text wird erkannt …")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        case .completed:
            Label("Text aus Bild erkannt", systemImage: "text.viewfinder")
                .font(.caption)
                .foregroundStyle(.green)
        case .noTextFound:
            Label("Kein Text im Bild gefunden", systemImage: "text.badge.xmark")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle")
                .font(.caption)
                .foregroundStyle(.orange)
        }
    }

    // MARK: - Bindings

    private var reminderDateBinding: Binding<Date> {
        Binding(
            get: { viewModel.reminderDate ?? Date().addingTimeInterval(3_600) },
            set: { viewModel.reminderDate = $0 }
        )
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )
    }

    // MARK: - Actions

    private func openCamera() async {
        guard viewModel.canAddMoreImages else {
            viewModel.errorMessage = ImageAttachmentPicker.limitMessage
            return
        }
        if let accessError = await ImageAttachmentPicker.cameraAccessError() {
            viewModel.errorMessage = accessError
            return
        }
        cameraSheet = CameraSheet()
    }

    private func loadSelectedPhotos(_ items: [PhotosPickerItem]) async {
        guard !items.isEmpty else { return }

        if let message = await ImageAttachmentPicker.loadPhotos(
            items,
            slotsLeft: viewModel.remainingImageSlots,
            addImage: { await viewModel.addImage($0) }
        ) {
            viewModel.errorMessage = message
        }

        selectedPhotoItems = []
    }

    private func save(forceNormalNote: Bool) {
        Task {
            do {
                try await viewModel.save(modelContext: modelContext, forceNormalNote: forceNormalNote)
                onSave()
            } catch {
                viewModel.errorMessage = error.localizedDescription
            }
        }
    }
}

// MARK: - View Extension für Card-Style

private extension View {
    func detailCard() -> some View {
        self
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
}
