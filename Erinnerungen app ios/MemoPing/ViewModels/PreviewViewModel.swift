import Combine
import Foundation
import SwiftData
import UIKit
import UserNotifications

enum PreviewValidationError: LocalizedError {
    case emptyDraft
    case pastReminderDate
    case imageLimitReached
    case ocrInProgress

    var errorDescription: String? {
        switch self {
        case .emptyDraft:
            return "Bitte erfasse Text oder füge ein Bild hinzu."
        case .pastReminderDate:
            return "Der Erinnerungstermin muss in der Zukunft liegen."
        case .imageLimitReached:
            return "Du kannst maximal 3 Bilder pro Memo hinzufügen."
        case .ocrInProgress:
            return "Bitte warte, bis die Texterkennung abgeschlossen ist."
        }
    }
}

enum OCRState: Equatable {
    case idle
    case processing
    case completed
    case noTextFound
    case failed(String)

    var isProcessing: Bool {
        if case .processing = self {
            return true
        }

        return false
    }

    var message: String? {
        switch self {
        case .idle:
            return nil
        case .processing:
            return "Text wird aus Bild erkannt..."
        case .completed:
            return "Text aus Bild erkannt."
        case .noTextFound:
            return "Kein Text im Bild erkannt."
        case .failed(let message):
            return message
        }
    }
}

struct PreviewImageAttachment: Identifiable {
    let fileName: String
    let image: UIImage

    var id: String { fileName }
}

struct DetectedDateSuggestion: Identifiable, Equatable {
    let date: Date
    let displayText: String
    let isFuture: Bool

    var id: String {
        "\(displayText)-\(date.timeIntervalSince1970)"
    }
}

@MainActor
final class PreviewViewModel: ObservableObject {
    @Published var title: String
    @Published var bodyText: String
    @Published var recognizedText: String
    @Published var reminderDate: Date?
    @Published var hasReminder = false
    @Published var reminderRepeatRule: MemoReminderRepeatRule = .none
    @Published var reminderLeadTime: MemoReminderLeadTime = .none
    @Published var syncsToCalendar = false
    @Published var categoryRawValue: String?
    @Published var priority: MemoPriority = .normal
    @Published private(set) var imageAttachments: [PreviewImageAttachment] = []
    @Published var detectedInfo: DetectedInfo
    @Published var didSkipPhotoQuestion = false
    @Published var isProcessingImage = false
    @Published var isSaving = false
    @Published private(set) var ocrState: OCRState = .idle
    @Published var errorMessage: String?
    @Published var notificationStatus: UNAuthorizationStatus = .notDetermined

    private var sourceType: MemoSourceType
    private var initialImages: [MemoDraftImage]
    private var didPersistImages = false
    private var activeOCRFileNames = Set<String>()
    private var completedOCRFileNames = Set<String>()
    private var noTextOCRFileNames = Set<String>()
    private var recognizedTextsByFileName: [String: String] = [:]
    private var ocrTasks: [String: Task<Void, Never>] = [:]
    private let ocrService = OCRService.shared
    private let dataDetectionService = DataDetectionService.shared
    private let imageStorage = ImageStorageService.shared
    private let notificationService = NotificationService.shared
    private let calendarSyncService = CalendarSyncService.shared

    init(draft: MemoDraft) {
        title = draft.title
        bodyText = draft.bodyText
        recognizedText = draft.recognizedText
        initialImages = draft.images
        detectedInfo = draft.detectedInfo
        sourceType = draft.sourceType
        reminderDate = draft.detectedInfo.dates.first { $0 > Date() }
        recalculateDetectedInfo()
    }

    var suggestedReminderDate: Date? {
        detectedInfo.dates.first { $0 > Date() }
    }

    var detectedDateStrings: [String] {
        detectedInfo.formattedDates()
    }

    var detectedDateSuggestions: [DetectedDateSuggestion] {
        detectedInfo.dates.enumerated().map { index, date in
            DetectedDateSuggestion(
                date: date,
                displayText: detectedInfo.dateStrings[safe: index] ?? date.germanFormatted(date: .abbreviated, time: .shortened),
                isFuture: date > Date()
            )
        }
    }

    var canSaveReminder: Bool {
        guard hasReminder, let reminderDate else {
            return false
        }

        return reminderDate > Date()
    }

    var notificationStatusText: String {
        NotificationService.statusText(for: notificationStatus)
    }

    var shouldShowNotificationPermissionButton: Bool {
        notificationStatus == .notDetermined || notificationStatus == .denied
    }

    var reminderValidationMessage: String? {
        guard hasReminder else {
            return nil
        }

        guard let reminderDate else {
            return "Bitte wähle ein Datum und eine Uhrzeit."
        }

        guard reminderDate > Date() else {
            return "Der Erinnerungstermin muss in der Zukunft liegen."
        }

        if reminderRepeatRule == .none,
           reminderLeadTime.hasLeadNotification,
           reminderDate.addingTimeInterval(-reminderLeadTime.timeInterval) <= Date() {
            return "Die Vorab-Erinnerung liegt bereits in der Vergangenheit."
        }

        return nil
    }

    var remainingImageSlots: Int {
        max(0, 3 - imageAttachments.count)
    }

    var canAddMoreImages: Bool {
        remainingImageSlots > 0
    }

    var imageLimitMessage: String? {
        canAddMoreImages ? nil : "Maximal 3 Bilder erreicht."
    }

    var canSave: Bool {
        !isSaving && !isProcessingImage && !ocrState.isProcessing
    }

    func acceptSuggestedReminder() {
        reminderDate = suggestedReminderDate
        hasReminder = reminderDate != nil
    }

    func useDetectedDate(_ date: Date) {
        reminderDate = date
        hasReminder = true
    }

    func textContentDidChange() {
        recalculateDetectedInfo()
    }

    func refreshNotificationStatus() async {
        notificationStatus = await notificationService.getAuthorizationStatus()
    }

    func requestNotificationAuthorization() async {
        do {
            let granted = try await notificationService.requestAuthorization()
            await refreshNotificationStatus()

            if !granted {
                errorMessage = "Benachrichtigungen wurden nicht erlaubt. Du kannst den Eintrag ohne Erinnerung speichern."
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func prepareInitialImagesIfNeeded() async {
        guard !initialImages.isEmpty else {
            return
        }

        let imagesToStore = initialImages
        initialImages = []

        for draftImage in imagesToStore {
            await addImage(draftImage.image, precomputedText: draftImage.recognizedText)
        }
    }

    /// `precomputedText` stammt aus dem Erfassen-Schritt: nil = OCR hier nachholen,
    /// "" = OCR lief ohne Treffer, sonst = erkannter Text (kein erneutes OCR nötig).
    func addImage(_ image: UIImage, precomputedText: String? = nil) async {
        guard canAddMoreImages else {
            errorMessage = PreviewValidationError.imageLimitReached.localizedDescription
            return
        }

        isProcessingImage = true
        defer { isProcessingImage = false }

        do {
            let fileName = try imageStorage.saveImage(image)
            let attachment = PreviewImageAttachment(fileName: fileName, image: image)
            imageAttachments.append(attachment)

            if let precomputedText {
                adoptPrecomputedText(precomputedText, for: fileName)
            } else {
                startOCR(for: attachment)
            }
        } catch {
            errorMessage = error.localizedDescription
            return
        }

        sourceType = bodyText.trimmed.isEmpty && recognizedText.trimmed.isEmpty ? .image : .mixed
        didSkipPhotoQuestion = false
    }

    private func adoptPrecomputedText(_ text: String, for fileName: String) {
        completedOCRFileNames.insert(fileName)

        let trimmedText = text.trimmed
        if trimmedText.isEmpty {
            noTextOCRFileNames.insert(fileName)
        } else {
            recognizedTextsByFileName[fileName] = trimmedText
            rebuildRecognizedTextFromImages()
        }

        updateOCRState()
    }

    func removeImage(_ attachment: PreviewImageAttachment) {
        cancelOCR(for: attachment.fileName)
        imageStorage.deleteImage(fileName: attachment.fileName)
        imageAttachments.removeAll { $0.id == attachment.id }
        recognizedTextsByFileName[attachment.fileName] = nil
        completedOCRFileNames.remove(attachment.fileName)
        noTextOCRFileNames.remove(attachment.fileName)
        if case .failed = ocrState {
            ocrState = .idle
        }
        rebuildRecognizedTextFromImages()
        updateOCRState()
    }

    func discardTemporaryImages() {
        guard !didPersistImages else {
            return
        }

        cancelAllOCR()
        imageStorage.deleteImages(fileNames: imageAttachments.map(\.fileName))
        imageAttachments.removeAll()
        recognizedTextsByFileName.removeAll()
        completedOCRFileNames.removeAll()
        noTextOCRFileNames.removeAll()
        ocrState = .idle
    }

    func save(modelContext: ModelContext, forceNormalNote: Bool = false) async throws {
        guard !ocrState.isProcessing else {
            throw PreviewValidationError.ocrInProgress
        }

        guard !title.trimmed.isEmpty || !bodyText.trimmed.isEmpty || !recognizedText.trimmed.isEmpty || !imageAttachments.isEmpty else {
            throw PreviewValidationError.emptyDraft
        }

        isSaving = true
        defer { isSaving = false }

        let now = Date()
        let shouldScheduleReminder = hasReminder && !forceNormalNote

        if shouldScheduleReminder {
            guard let reminderDate, reminderDate > now else {
                throw PreviewValidationError.pastReminderDate
            }

            if reminderRepeatRule == .none,
               reminderLeadTime.hasLeadNotification,
               reminderDate.addingTimeInterval(-reminderLeadTime.timeInterval) <= now {
                throw NotificationServiceError.leadDateInPast
            }
        }

        let storedImageNames = imageAttachments.map(\.fileName)
        let finalTitle = generatedTitle()
        let infoToStore = detectedInfo.sanitized()
        var createdCalendarEventIdentifier: String?

        let memo = MemoItem(
            title: finalTitle,
            bodyText: bodyText.trimmed,
            recognizedText: recognizedText.trimmed,
            reminderDate: shouldScheduleReminder ? reminderDate : nil,
            hasReminder: shouldScheduleReminder,
            reminderRepeatRule: shouldScheduleReminder ? reminderRepeatRule : .none,
            reminderLeadTime: shouldScheduleReminder ? reminderLeadTime : .none,
            syncsToCalendar: shouldScheduleReminder && syncsToCalendar,
            priority: priority,
            categoryRawValue: categoryRawValue,
            sourceType: sourceType,
            imageFileNames: storedImageNames,
            detectedPhoneNumbers: infoToStore.phoneNumbers,
            detectedURLs: infoToStore.urls,
            detectedAddresses: infoToStore.addresses,
            detectedDateStrings: infoToStore.formattedDates()
        )

        do {
            modelContext.insert(memo)
            try modelContext.save()

            if shouldScheduleReminder {
                try await notificationService.scheduleReminder(for: memo)
            }

            if shouldScheduleReminder && syncsToCalendar {
                createdCalendarEventIdentifier = try await calendarSyncService.saveEvent(for: memo)
                memo.calendarEventIdentifier = createdCalendarEventIdentifier
                try modelContext.save()
            }

            MemoWidgetSnapshotUpdater.refresh(in: modelContext)
            didPersistImages = true
        } catch {
            if let createdCalendarEventIdentifier {
                try? await calendarSyncService.deleteEvent(with: createdCalendarEventIdentifier)
            }

            if shouldScheduleReminder {
                notificationService.cancelReminder(for: memo)
            }

            // Nur das Memo zurückrollen — Bilddateien und Attachments bleiben
            // erhalten, damit nach einem Fehler (z. B. verweigerte Benachrichtigung)
            // keine Fotos verloren gehen und erneut gespeichert werden kann.
            // Die Discard-Pfade räumen die Dateien weiterhin auf.
            modelContext.delete(memo)
            try? modelContext.save()
            await refreshNotificationStatus()
            throw error
        }
    }

    private func appendRecognizedText(_ text: String) {
        recalculateDetectedInfo()

        if reminderDate == nil {
            reminderDate = suggestedReminderDate
        }
    }

    private func recalculateDetectedInfo() {
        let combinedText = [bodyText, recognizedText]
            .map(\.trimmed)
            .filter { !$0.isEmpty }
            .joined(separator: "\n")

        guard !combinedText.isEmpty else {
            detectedInfo = DetectedInfo()
            return
        }

        detectedInfo = dataDetectionService.detect(in: combinedText)
    }

    private func startOCR(for attachment: PreviewImageAttachment) {
        guard ocrTasks[attachment.fileName] == nil,
              !completedOCRFileNames.contains(attachment.fileName) else {
            return
        }

        activeOCRFileNames.insert(attachment.fileName)
        updateOCRState()

        ocrTasks[attachment.fileName] = Task { [weak self] in
            await self?.runOCR(for: attachment)
        }
    }

    private func runOCR(for attachment: PreviewImageAttachment) async {
        defer {
            activeOCRFileNames.remove(attachment.fileName)
            ocrTasks[attachment.fileName] = nil
            updateOCRState()
        }

        do {
            let text = try await ocrService.recognizeText(in: attachment.image)
            guard !Task.isCancelled, imageAttachments.contains(where: { $0.fileName == attachment.fileName }) else {
                return
            }

            completedOCRFileNames.insert(attachment.fileName)
            noTextOCRFileNames.remove(attachment.fileName)
            recognizedTextsByFileName[attachment.fileName] = text
            rebuildRecognizedTextFromImages()
            appendRecognizedText(text)
        } catch is CancellationError {
            return
        } catch OCRServiceError.noTextFound {
            guard !Task.isCancelled, imageAttachments.contains(where: { $0.fileName == attachment.fileName }) else {
                return
            }

            completedOCRFileNames.insert(attachment.fileName)
            noTextOCRFileNames.insert(attachment.fileName)
        } catch {
            guard !Task.isCancelled, imageAttachments.contains(where: { $0.fileName == attachment.fileName }) else {
                return
            }

            completedOCRFileNames.insert(attachment.fileName)
            ocrState = .failed("Das Bild wurde hinzugefügt. Texterkennung war nicht möglich: \(error.localizedDescription)")
            errorMessage = ocrState.message
        }
    }

    private func cancelOCR(for fileName: String) {
        ocrTasks[fileName]?.cancel()
        ocrTasks[fileName] = nil
        activeOCRFileNames.remove(fileName)
    }

    private func cancelAllOCR() {
        ocrTasks.values.forEach { $0.cancel() }
        ocrTasks.removeAll()
        activeOCRFileNames.removeAll()
    }

    private func rebuildRecognizedTextFromImages() {
        let sections = imageAttachments.enumerated().compactMap { index, attachment -> String? in
            guard let text = recognizedTextsByFileName[attachment.fileName]?.trimmed,
                  !text.isEmpty else {
                return nil
            }

            return "--- Bild \(index + 1) ---\n\(text)"
        }

        recognizedText = sections.joined(separator: "\n\n")
    }

    private func updateOCRState() {
        if !activeOCRFileNames.isEmpty {
            ocrState = .processing
            return
        }

        guard !imageAttachments.isEmpty else {
            ocrState = .idle
            return
        }

        if !recognizedTextsByFileName.isEmpty {
            ocrState = .completed
            return
        }

        let currentImageFileNames = Set(imageAttachments.map(\.fileName))
        if !currentImageFileNames.isEmpty && currentImageFileNames.isSubset(of: noTextOCRFileNames) {
            ocrState = .noTextFound
        } else if case .failed = ocrState {
            return
        } else {
            ocrState = .idle
        }
    }

    private func generatedTitle() -> String {
        let manualTitle = title.trimmed
        if !manualTitle.isEmpty {
            return manualTitle
        }

        let source = bodyText.trimmed.isEmpty ? recognizedText.trimmed : bodyText.trimmed
        if source.isEmpty {
            return imageAttachments.isEmpty ? "Neue Notiz" : "Bildnotiz"
        }

        let words = source
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .prefix(6)
            .joined(separator: " ")

        return words.isEmpty ? "Neue Notiz" : words
    }
}

private extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
