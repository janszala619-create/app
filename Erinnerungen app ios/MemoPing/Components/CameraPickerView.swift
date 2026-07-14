import AVFoundation
import PhotosUI
import SwiftUI
import UIKit

struct CameraSheet: Identifiable {
    let id = UUID()
}

/// Gemeinsame Kamera-/Galerie-Logik von CaptureView und PreviewView —
/// die beiden Flows hielten zuvor nahezu identische Kopien davon.
@MainActor
enum ImageAttachmentPicker {
    static let limitMessage = "Du kannst maximal 3 Bilder pro Memo hinzufügen."

    /// Prüft Verfügbarkeit und Berechtigung der Kamera und fragt die
    /// Berechtigung bei Bedarf an. Liefert eine anzeigbare Fehlermeldung
    /// oder nil, wenn die Kamera geöffnet werden darf.
    static func cameraAccessError() async -> String? {
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
            return "Kamera ist auf diesem Gerät nicht verfügbar."
        }

        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            return granted ? nil : "Die Kameraberechtigung wurde nicht erteilt."
        case .denied, .restricted:
            return "Die Kameraberechtigung wurde nicht erteilt. Bitte in den Einstellungen aktivieren."
        default:
            return nil
        }
    }

    /// Lädt die PhotosPicker-Auswahl und reicht jedes Bild an `addImage`
    /// weiter, begrenzt auf die freien Slots. Liefert eine anzeigbare
    /// Hinweis-/Fehlermeldung oder nil.
    static func loadPhotos(
        _ items: [PhotosPickerItem],
        slotsLeft: Int,
        addImage: (UIImage) async -> Void
    ) async -> String? {
        guard slotsLeft > 0 else { return limitMessage }

        var loadFailed = false
        for item in items.prefix(slotsLeft) {
            do {
                if let data = try await item.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    await addImage(image)
                }
            } catch {
                loadFailed = true
            }
        }

        if loadFailed {
            return "Bild konnte nicht geladen werden."
        }
        if items.count > slotsLeft {
            return "Es wurden nur \(slotsLeft) Bilder übernommen. Maximal 3 pro Memo."
        }
        return nil
    }
}

struct CameraPickerView: UIViewControllerRepresentable {
    var onImagePicked: (UIImage) -> Void

    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.mediaTypes = ["public.image"]
        picker.cameraCaptureMode = .photo
        picker.allowsEditing = false
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        private let parent: CameraPickerView

        init(parent: CameraPickerView) {
            self.parent = parent
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            if let image = info[.originalImage] as? UIImage {
                parent.onImagePicked(image)
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}
