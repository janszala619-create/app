import Combine
import Foundation
import UIKit

struct CaptureImageAttachment: Identifiable {
    let id = UUID()
    let image: UIImage
    var recognizedText: String?
}

@MainActor
final class CaptureViewModel: ObservableObject {
    @Published var inputText = ""
    @Published var recognizedText = ""
    @Published var detectedInfo = DetectedInfo()
    @Published private(set) var imageAttachments: [CaptureImageAttachment] = []
    @Published var isRecording = false
    @Published var isPreparingSpeech = false
    @Published var hasAttemptedSpeechInput = false
    @Published var isProcessingImage = false
    @Published var errorMessage: String?
    @Published var sourceType: MemoSourceType = .text

    private let speechService = SpeechRecognitionService()
    private let ocrService = OCRService.shared
    private let dataDetectionService = DataDetectionService.shared
    private var cancellables: Set<AnyCancellable> = []

    init() {
        speechService.$transcript
            .receive(on: RunLoop.main)
            .sink { [weak self] transcript in
                guard let self, !transcript.trimmed.isEmpty else { return }
                self.inputText = transcript
                self.sourceType = .voice
                self.recalculateDetectedInfo()
            }
            .store(in: &cancellables)

        speechService.$isRecording
            .receive(on: RunLoop.main)
            .assign(to: &$isRecording)

        speechService.$errorMessage
            .receive(on: RunLoop.main)
            .sink { [weak self] message in
                guard let message else { return }
                self?.errorMessage = message
            }
            .store(in: &cancellables)
    }

    var canContinue: Bool {
        !inputText.trimmed.isEmpty || !recognizedText.trimmed.isEmpty || !imageAttachments.isEmpty
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

    var speechStatusText: String {
        if isPreparingSpeech {
            return "Transkription wird erstellt..."
        }

        if isRecording {
            return "Aufnahme läuft..."
        }

        if !inputText.trimmed.isEmpty {
            return "Transkription verfügbar"
        }

        if hasAttemptedSpeechInput && inputText.trimmed.isEmpty {
            return "Keine Sprache erkannt"
        }

        return "Bereit"
    }

    var speechButtonTitle: String {
        isRecording ? "Aufnahme stoppen" : "Aufnahme starten"
    }

    var emptyTextHint: String? {
        canContinue ? nil : "Sprich etwas ein, gib Text ein oder füge ein Bild hinzu."
    }

    func toggleRecording() {
        if isRecording {
            stopRecording()
        } else {
            Task {
                await startRecording()
            }
        }
    }

    func stopRecording() {
        hasAttemptedSpeechInput = true
        speechService.stopRecording()
        isRecording = false
        isPreparingSpeech = false
        recalculateDetectedInfo()
    }

    func cancelRecording() {
        speechService.cancelRecording()
        isRecording = false
        isPreparingSpeech = false
    }

    func textDidChange() {
        if !inputText.trimmed.isEmpty {
            sourceType = sourceType == .image ? .mixed : sourceType
        }
        recalculateDetectedInfo()
    }

    func addImage(_ image: UIImage) async {
        guard canAddMoreImages else {
            errorMessage = "Du kannst maximal 3 Bilder pro Memo hinzufügen."
            return
        }

        let attachment = CaptureImageAttachment(image: image)
        imageAttachments.append(attachment)
        sourceType = sourceType == .text && inputText.trimmed.isEmpty ? .image : .mixed
        isProcessingImage = true
        defer { isProcessingImage = false }

        do {
            let text = try await ocrService.recognizeText(in: image)
            guard let index = imageAttachments.firstIndex(where: { $0.id == attachment.id }) else {
                return
            }

            imageAttachments[index].recognizedText = text
            rebuildRecognizedText()
        } catch OCRServiceError.noTextFound {
            errorMessage = "Im Bild wurde kein Text erkannt."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func removeImage(_ attachment: CaptureImageAttachment) {
        imageAttachments.removeAll { $0.id == attachment.id }
        rebuildRecognizedText()

        if imageAttachments.isEmpty, inputText.trimmed.isEmpty {
            sourceType = .text
        }
    }

    func makeDraft() -> MemoDraft {
        let info = dataDetectionService.detect(in: [inputText, recognizedText].joined(separator: "\n"))

        return MemoDraft(
            title: "",
            bodyText: inputText.trimmed,
            recognizedText: recognizedText.trimmed,
            images: imageAttachments.map(\.image),
            sourceType: sourceType,
            detectedInfo: info
        )
    }

    private func startRecording() async {
        guard !isRecording, !isPreparingSpeech else {
            return
        }

        hasAttemptedSpeechInput = true
        isPreparingSpeech = true
        await speechService.startRecording()
        isPreparingSpeech = false
    }

    private func rebuildRecognizedText() {
        let sections = imageAttachments.enumerated().compactMap { index, attachment -> String? in
            guard let text = attachment.recognizedText?.trimmed, !text.isEmpty else {
                return nil
            }

            return "--- Bild \(index + 1) ---\n\(text)"
        }

        recognizedText = sections.joined(separator: "\n\n")
        recalculateDetectedInfo()
    }

    private func recalculateDetectedInfo() {
        detectedInfo = dataDetectionService.detect(in: [inputText, recognizedText].joined(separator: "\n"))
    }
}

extension String {
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
