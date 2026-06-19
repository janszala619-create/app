import AVFoundation
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
        Form {
            contentSection
            reminderSection
            photoQuestionSection
            imagesSection
            detectedInfoSection
            organizationSection
            saveSection
        }
        .scrollContentBackground(.hidden)
        .background(
            LinearGradient(
                colors: [
                    Color(red: 0.03, green: 0.03, blue: 0.06),
                    Color(red: 0.06, green: 0.04, blue: 0.10),
                    Color(red: 0.02, green: 0.02, blue: 0.04)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .tint(Color(red: 0.56, green: 0.34, blue: 1.0))
        .preferredColorScheme(.dark)
        .scrollDismissesKeyboard(.interactively)
        .onChange(of: selectedPhotoItems) { _, newItems in
            Task {
                await loadSelectedPhotos(newItems)
            }
        }
        .onChange(of: viewModel.bodyText) { _, _ in
            viewModel.textContentDidChange()
        }
        .onChange(of: viewModel.recognizedText) { _, _ in
            viewModel.textContentDidChange()
        }
        .task {
            await viewModel.refreshNotificationStatus()
            await viewModel.prepareInitialImagesIfNeeded()
        }
        .sheet(item: $cameraSheet) { _ in
            CameraPickerView { image in
                Task {
                    await viewModel.addImage(image)
                }
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
            Button("OK", role: .cancel) {
                viewModel.errorMessage = nil
            }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }

    private var contentSection: some View {
        Section("Inhalt") {
            TextField("Titel", text: $viewModel.title)
                .font(.title.weight(.bold))

            VStack(alignment: .leading, spacing: 8) {
                Text("Notiztext")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                TextEditor(text: $viewModel.bodyText)
                    .frame(minHeight: 120)
            }

            if !viewModel.recognizedText.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Erkannter Text aus Bildern")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    TextEditor(text: $viewModel.recognizedText)
                        .frame(minHeight: 110)
                }
            }
        }
        .listRowBackground(formRowBackground)
    }

    private var photoQuestionSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                Text("Möchtest du ein Foto hinzufügen?")
                    .font(.headline)

                HStack(spacing: 10) {
                    Button {
                        Task {
                            await openCamera()
                        }
                    } label: {
                        Label("Foto aufnehmen", systemImage: "camera")
                    }
                    .buttonStyle(.bordered)
                    .disabled(!viewModel.canAddMoreImages)

                    if viewModel.canAddMoreImages {
                        PhotosPicker(
                            selection: $selectedPhotoItems,
                            maxSelectionCount: viewModel.remainingImageSlots,
                            matching: .images
                        ) {
                            Label("Aus Galerie wählen", systemImage: "photo")
                        }
                        .buttonStyle(.bordered)
                    } else {
                        Button {
                            viewModel.errorMessage = "Du kannst maximal 3 Bilder pro Memo hinzufügen."
                        } label: {
                            Label("Aus Galerie wählen", systemImage: "photo")
                        }
                        .buttonStyle(.bordered)
                        .disabled(true)
                    }
                }

                if let imageLimitMessage = viewModel.imageLimitMessage {
                    Label(imageLimitMessage, systemImage: "info.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if viewModel.imageAttachments.isEmpty {
                    Label("Noch kein Foto hinzugefügt.", systemImage: "photo")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Button {
                    viewModel.didSkipPhotoQuestion = true
                } label: {
                    Label("Überspringen", systemImage: "forward")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)

                if viewModel.didSkipPhotoQuestion {
                    Label("Kein Foto für diesen Eintrag", systemImage: "checkmark.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if viewModel.isProcessingImage {
                    ProgressView("Bild wird vorbereitet")
                }

                ocrStatusView
            }
            .padding(.vertical, 4)
        }
        .listRowBackground(formRowBackground)
    }

    private var reminderSection: some View {
        Section("Erinnerung") {
            if let suggestedDate = viewModel.suggestedReminderDate, !viewModel.hasReminder {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Soll daraus eine Erinnerung erstellt werden?")
                        .font(.headline)

                    Text(suggestedDate.formatted(date: .abbreviated, time: .shortened))
                        .foregroundStyle(.secondary)

                    Button {
                        viewModel.acceptSuggestedReminder()
                    } label: {
                        Label("Datum übernehmen", systemImage: "bell.badge")
                    }
                }
                .padding(.vertical, 4)
            }

            Toggle("Als Erinnerung speichern", isOn: $viewModel.hasReminder)

            if viewModel.hasReminder {
                DatePicker(
                    "Datum und Uhrzeit",
                    selection: reminderDateBinding,
                    in: Date()...,
                    displayedComponents: [.date, .hourAndMinute]
                )

                Picker("Wiederholen", selection: $viewModel.reminderRepeatRule) {
                    ForEach(MemoReminderRepeatRule.allCases) { repeatRule in
                        Label(repeatRule.displayName, systemImage: repeatRule.systemImage)
                            .tag(repeatRule)
                    }
                }

                Picker("Vorher erinnern", selection: $viewModel.reminderLeadTime) {
                    ForEach(MemoReminderLeadTime.allCases) { leadTime in
                        Label(leadTime.displayName, systemImage: leadTime.systemImage)
                            .tag(leadTime)
                    }
                }

                Toggle("Mit iOS-Kalender synchronisieren", isOn: $viewModel.syncsToCalendar)

                if viewModel.syncsToCalendar {
                    Label("RemindlyAi erstellt dafür einen Termin im iOS-Kalender und aktualisiert ihn bei Änderungen.", systemImage: "calendar.badge.plus")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let reminderValidationMessage = viewModel.reminderValidationMessage {
                    Label(reminderValidationMessage, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Label("Benachrichtigungen", systemImage: "bell")
                        Spacer()
                        Text(viewModel.notificationStatusText)
                            .foregroundStyle(.secondary)
                    }

                    if viewModel.notificationStatus != .authorized {
                        Text("RemindlyAi plant Erinnerungen lokal auf diesem iPhone. Dafür müssen Benachrichtigungen erlaubt sein.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if viewModel.shouldShowNotificationPermissionButton {
                        Button {
                            Task {
                                await viewModel.requestNotificationAuthorization()
                            }
                        } label: {
                            Label("Benachrichtigungen erlauben", systemImage: "bell.badge")
                        }
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .listRowBackground(formRowBackground)
    }

    private var organizationSection: some View {
        Section("Einordnung") {
            CategoryPickerView(selectionRawValue: $viewModel.categoryRawValue, categories: categories)
            PriorityPickerView(selection: $viewModel.priority)
        }
        .listRowBackground(formRowBackground)
    }

    @ViewBuilder
    private var detectedInfoSection: some View {
        Section("Erkannte Informationen") {
            if viewModel.detectedInfo.isEmpty {
                Label("Noch keine erkannten Informationen.", systemImage: "text.magnifyingglass")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                if !viewModel.detectedDateSuggestions.isEmpty {
                    detectedDateRows(viewModel.detectedDateSuggestions)
                }

                if !viewModel.detectedInfo.phoneNumbers.isEmpty {
                    editableDetectedRows(title: "Telefonnummern", systemImage: "phone", values: $viewModel.detectedInfo.phoneNumbers)
                }

                if !viewModel.detectedInfo.urls.isEmpty {
                    editableDetectedRows(title: "Links", systemImage: "link", values: $viewModel.detectedInfo.urls)
                }

                if !viewModel.detectedInfo.addresses.isEmpty {
                    editableDetectedRows(title: "Adressen", systemImage: "mappin.and.ellipse", values: $viewModel.detectedInfo.addresses)
                }
            }
        }
        .listRowBackground(formRowBackground)
    }

    @ViewBuilder
    private var imagesSection: some View {
        if !viewModel.imageAttachments.isEmpty {
            Section("Bilder") {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(viewModel.imageAttachments) { attachment in
                            ZStack(alignment: .topTrailing) {
                                Image(uiImage: attachment.image)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 112, height: 112)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))

                                Button {
                                    viewModel.removeImage(attachment)
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.title3)
                                        .symbolRenderingMode(.palette)
                                        .foregroundStyle(.white, .black.opacity(0.65))
                                }
                                .buttonStyle(.plain)
                                .padding(6)
                                .accessibilityLabel("Bild entfernen")
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .listRowBackground(formRowBackground)
        }
    }

    private var saveSection: some View {
        Section {
            Button {
                save(forceNormalNote: false)
            } label: {
                Label(viewModel.hasReminder ? "Als Erinnerung speichern" : "Notiz speichern", systemImage: viewModel.hasReminder ? "bell" : "note.text")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!viewModel.canSave)

            if viewModel.hasReminder {
                Button {
                    save(forceNormalNote: true)
                } label: {
                    Label("Ohne Erinnerung speichern", systemImage: "bell.slash")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(!viewModel.canSave)
            }

            Button(role: .destructive) {
                showDiscardConfirmation = true
            } label: {
                Label("Verwerfen", systemImage: "trash")
                    .frame(maxWidth: .infinity)
            }
        }
        .listRowBackground(Color.clear)
    }

    private var formRowBackground: Color {
        Color.white.opacity(0.07)
    }

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

    @ViewBuilder
    private var ocrStatusView: some View {
        switch viewModel.ocrState {
        case .idle:
            EmptyView()
        case .processing:
            ProgressView("Text wird aus Bild erkannt...")
                .font(.caption)
        case .completed:
            Label("Text aus Bild erkannt.", systemImage: "text.viewfinder")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .noTextFound:
            Label("Kein Text im Bild erkannt.", systemImage: "text.badge.xmark")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle")
                .font(.caption)
                .foregroundStyle(.orange)
        }
    }

    private func detectedDateRows(_ suggestions: [DetectedDateSuggestion]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Erkannte Termine", systemImage: "calendar")
                .font(.subheadline.weight(.semibold))

            ForEach(suggestions) { suggestion in
                let index = suggestions.firstIndex(of: suggestion) ?? 0

                VStack(alignment: .leading, spacing: 6) {
                    TextField("Erkannter Termin", text: detectedDateStringBinding(at: index))
                        .textInputAutocapitalization(.sentences)

                    if suggestion.isFuture {
                        Button {
                            viewModel.useDetectedDate(suggestion.date)
                        } label: {
                            Label("Als Erinnerung verwenden", systemImage: "bell.badge")
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
        }
    }

    private func editableDetectedRows(title: String, systemImage: String, values: Binding<[String]>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.semibold))

            ForEach(values.wrappedValue.indices, id: \.self) { index in
                TextField(title, text: detectedStringBinding(values, at: index))
                    .textInputAutocapitalization(.never)
                    .keyboardType(title == "Telefonnummern" ? .phonePad : .default)
            }
        }
    }

    private func detectedDateStringBinding(at index: Int) -> Binding<String> {
        Binding(
            get: {
                viewModel.detectedInfo.dateStrings[safe: index] ?? viewModel.detectedDateSuggestions[safe: index]?.displayText ?? ""
            },
            set: { newValue in
                guard viewModel.detectedInfo.dateStrings.indices.contains(index) else {
                    return
                }

                viewModel.detectedInfo.dateStrings[index] = newValue
            }
        )
    }

    private func detectedStringBinding(_ values: Binding<[String]>, at index: Int) -> Binding<String> {
        Binding(
            get: {
                values.wrappedValue[safe: index] ?? ""
            },
            set: { newValue in
                guard values.wrappedValue.indices.contains(index) else {
                    return
                }

                values.wrappedValue[index] = newValue
            }
        )
    }

    private func detectedRows(title: String, systemImage: String, values: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.semibold))

            ForEach(values, id: \.self) { value in
                Text(value)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
    }

    private func openCamera() async {
        guard viewModel.canAddMoreImages else {
            viewModel.errorMessage = "Du kannst maximal 3 Bilder pro Memo hinzufügen."
            return
        }

        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
            viewModel.errorMessage = "Kamera ist auf diesem Gerät nicht verfügbar."
            return
        }

        let status = AVCaptureDevice.authorizationStatus(for: .video)
        if status == .notDetermined {
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            guard granted else {
                viewModel.errorMessage = "Die Kameraberechtigung wurde nicht erteilt."
                return
            }
        } else if status == .denied || status == .restricted {
            viewModel.errorMessage = "Die Kameraberechtigung wurde nicht erteilt."
            return
        }

        cameraSheet = CameraSheet()
    }

    private func loadSelectedPhotos(_ items: [PhotosPickerItem]) async {
        guard !items.isEmpty else { return }

        guard viewModel.canAddMoreImages else {
            viewModel.errorMessage = "Du kannst maximal 3 Bilder pro Memo hinzufügen."
            selectedPhotoItems = []
            return
        }

        let itemsToLoad = Array(items.prefix(viewModel.remainingImageSlots))

        for item in itemsToLoad {
            do {
                if let data = try await item.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    await viewModel.addImage(image)
                } else {
                    viewModel.errorMessage = "Das ausgewählte Bild konnte nicht geladen werden."
                }
            } catch {
                viewModel.errorMessage = "Das ausgewählte Bild konnte nicht geladen werden: \(error.localizedDescription)"
            }
        }

        if items.count > itemsToLoad.count {
            viewModel.errorMessage = "Es wurden nur die ersten \(itemsToLoad.count) Bilder übernommen. Maximal 3 Bilder pro Memo sind erlaubt."
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

private extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
