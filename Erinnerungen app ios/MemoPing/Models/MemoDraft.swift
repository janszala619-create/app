import UIKit

/// Bild aus dem Erfassen-Schritt inklusive bereits erkanntem Text,
/// damit die Vorschau das OCR nicht erneut ausführen muss.
/// `recognizedText`: nil = OCR ausstehend/fehlgeschlagen, "" = gelaufen ohne Treffer.
struct MemoDraftImage {
    let image: UIImage
    var recognizedText: String?
}

struct MemoDraft {
    var title: String = ""
    var bodyText: String = ""
    var recognizedText: String = ""
    var images: [MemoDraftImage] = []
    var sourceType: MemoSourceType = .text
    var detectedInfo: DetectedInfo = DetectedInfo()
}
