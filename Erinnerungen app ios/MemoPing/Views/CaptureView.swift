import PhotosUI
import SwiftUI

struct CaptureView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    @StateObject private var viewModel = CaptureViewModel()
    @State private var previewViewModel: PreviewViewModel?
    @State private var selectedPhotoItems: [PhotosPickerItem] = []
    @State private var cameraSheet: CameraSheet?

    let onComplete: () -> Void

    var body: some View {
        NavigationStack {
            Group {
                if let previewViewModel {
                    PreviewView(
                        viewModel: previewViewModel,
                        onSave: onComplete,
                        onDiscard: { dismiss() }
                    )
                } else {
                    captureContent
                }
            }
            .navigationTitle(previewViewModel == nil ? "Erfassen" : "Vorschau")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if previewViewModel == nil {
                        Button("Abbrechen") {
                            viewModel.cancelRecording()
                            dismiss()
                        }
                    } else {
                        Button("Zurück") {
                            previewViewModel?.discardTemporaryImages()
                            previewViewModel = nil
                        }
                    }
                }
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase != .active {
                viewModel.stopRecording()
            }
        }
        .onChange(of: selectedPhotoItems) { _, newItems in
            Task { await loadSelectedPhotos(newItems) }
        }
        .onDisappear {
            previewViewModel?.discardTemporaryImages()
            viewModel.cancelRecording()
        }
        .sheet(item: $cameraSheet) { _ in
            CameraPickerView { image in
                Task { await viewModel.addImage(image) }
            }
        }
        .alert("Hinweis", isPresented: errorBinding) {
            Button("OK", role: .cancel) { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }

    // MARK: - Capture Content

    private var captureContent: some View {
        ScrollView {
            VStack(spacing: 16) {
                headerCard
                textSection
                imageSection
                voiceSection
                continueButton
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(Color(.systemGroupedBackground))
        .onChange(of: viewModel.inputText) { _, _ in
            viewModel.textDidChange()
        }
    }

    // MARK: - Header

    private var headerCard: some View {
        HStack(spacing: 14) {
            Image(systemName: "sparkles")
                .font(.title2.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(Color.accentColor.gradient, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text("Schnell erfassen")
                    .font(.headline)
                Text("Text, Sprache oder Bild")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: - Text Section

    private var textSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Text eingeben", systemImage: "keyboard")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)

            TextEditor(text: $viewModel.inputText)
                .frame(minHeight: 120)
                .padding(12)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay {
                    if viewModel.inputText.isEmpty {
                        Text("Notiz oder Erinnerung eingeben …")
                            .foregroundStyle(.tertiary)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                            .padding(.top, 20)
                            .padding(.leading, 16)
                            .allowsHitTesting(false)
                    }
                }
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: - Image Section (Fix B)

    private var imageSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Bild hinzufügen", systemImage: "photo.on.rectangle")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)

            // Vorschau bereits hinzugefügter Bilder
            if !viewModel.imageAttachments.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(Array(viewModel.imageAttachments.enumerated()), id: \.element.id) { index, attachment in
                            ZStack(alignment: .topTrailing) {
                                Image(uiImage: attachment.image)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 90, height: 90)
                                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

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
                                .accessibilityLabel("Bild \(index + 1) entfernen")
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
            }

            // Buttons: Kamera + Galerie
            HStack(spacing: 10) {
                // Kamera
                Button {
                    Task { await openCamera() }
                } label: {
                    Label("Foto aufnehmen", systemImage: "camera")
                        .font(.subheadline.weight(.medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.bordered)
                .disabled(!viewModel.canAddMoreImages)

                // Galerie
                PhotosPicker(
                    selection: $selectedPhotoItems,
                    maxSelectionCount: viewModel.remainingImageSlots,
                    matching: .images
                ) {
                    Label("Aus Galerie", systemImage: "photo")
                        .font(.subheadline.weight(.medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.bordered)
                .disabled(!viewModel.canAddMoreImages)
            }

            // Statuszeile
            if viewModel.isProcessingImage {
                HStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Bild wird verarbeitet …")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else if !viewModel.canAddMoreImages {
                Label("Maximal 3 Bilder pro Memo", systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Label("Foto oder Screenshot direkt einfügbar", systemImage: "photo.badge.plus")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: - Voice Section

    private var voiceSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Sprache aufnehmen", systemImage: "mic")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)

            Button {
                viewModel.toggleRecording()
            } label: {
                HStack(spacing: 14) {
                    ZStack {
                        Circle()
                            .fill(viewModel.isRecording ? Color.red : Color.accentColor)
                            .frame(width: 52, height: 52)

                        Image(systemName: viewModel.isRecording ? "stop.fill" : "mic.fill")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.white)
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        Text(viewModel.speechButtonTitle)
                            .font(.headline)
                            .foregroundStyle(.primary)

                        Label(viewModel.speechStatusText, systemImage: viewModel.isRecording ? "waveform" : "mic")
                            .font(.subheadline)
                            .foregroundStyle(viewModel.isRecording ? .red : .secondary)
                    }

                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(viewModel.isPreparingSpeech)
            .accessibilityLabel(viewModel.isRecording ? "Aufnahme stoppen" : "Sprache aufnehmen")

            Text("Spracherkennung via iOS. Memos bleiben lokal auf dem Gerät.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: - Continue Button

    private var continueButton: some View {
        VStack(spacing: 10) {
            if let hint = viewModel.emptyTextHint {
                Label(hint, systemImage: "info.circle")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Button {
                openPreview()
            } label: {
                Label("Zur Vorschau", systemImage: "arrow.right")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!viewModel.canContinue || viewModel.isProcessingImage)
        }
        .padding(.bottom, 8)
    }

    // MARK: - Helpers

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )
    }

    private func openPreview() {
        guard viewModel.canContinue else {
            viewModel.errorMessage = "Bitte erfasse Text oder füge ein Bild hinzu."
            return
        }
        viewModel.stopRecording()
        previewViewModel = PreviewViewModel(draft: viewModel.makeDraft())
    }

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
}
