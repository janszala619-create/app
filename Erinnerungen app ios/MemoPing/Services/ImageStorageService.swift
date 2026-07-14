import UIKit

enum ImageStorageError: LocalizedError {
    case cannotCreateData
    case cannotLoadDirectory

    var errorDescription: String? {
        switch self {
        case .cannotCreateData:
            return "Das Bild konnte nicht gespeichert werden."
        case .cannotLoadDirectory:
            return "Der lokale Bildspeicher konnte nicht vorbereitet werden."
        }
    }
}

final class ImageStorageService {
    static let shared = ImageStorageService()

    private let folderName = "MemoPingImages"
    private var didEnsureBackupInclusion = false

    private init() {}

    func saveImage(_ image: UIImage, compressionQuality: CGFloat = 0.86) throws -> String {
        let preparedImage = image.resizedForMemoStorage(maxPixelDimension: 2_000)

        guard let data = preparedImage.jpegData(compressionQuality: compressionQuality) else {
            throw ImageStorageError.cannotCreateData
        }

        let fileName = "\(UUID().uuidString).jpg"
        let fileURL = try imageDirectory().appendingPathComponent(fileName)
        try data.write(to: fileURL, options: [.atomic])
        return fileName
    }

    func loadImage(fileName: String) -> UIImage? {
        guard let directory = try? imageDirectory() else {
            return nil
        }

        return UIImage(contentsOfFile: directory.appendingPathComponent(fileName).path)
    }

    func deleteImage(fileName: String) {
        guard let directory = try? imageDirectory() else {
            return
        }

        try? FileManager.default.removeItem(at: directory.appendingPathComponent(fileName))
    }

    func deleteImages(fileNames: [String]) {
        fileNames.forEach(deleteImage(fileName:))
    }

    private func imageDirectory() throws -> URL {
        guard let supportDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw ImageStorageError.cannotLoadDirectory
        }

        var directory = supportDirectory.appendingPathComponent(folderName, isDirectory: true)

        if !FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }

        // Memo-Bilder sind Nutzdaten und müssen ins iCloud-/Geräte-Backup.
        // Frühere Versionen hatten den Ordner vom Backup ausgeschlossen; das
        // wird hier für bestehende Installationen einmalig zurückgenommen.
        if !didEnsureBackupInclusion {
            var values = URLResourceValues()
            values.isExcludedFromBackup = false
            try? directory.setResourceValues(values)
            didEnsureBackupInclusion = true
        }

        return directory
    }
}

extension ImageStorageService {
    func save(_ image: UIImage) throws -> String {
        try saveImage(image)
    }

    func load(fileName: String) -> UIImage? {
        loadImage(fileName: fileName)
    }

    func delete(fileName: String) {
        deleteImage(fileName: fileName)
    }

    func delete(fileNames: [String]) {
        deleteImages(fileNames: fileNames)
    }
}

private extension UIImage {
    func resizedForMemoStorage(maxPixelDimension: CGFloat) -> UIImage {
        let longestSide = max(size.width, size.height)

        guard longestSide > maxPixelDimension else {
            return self
        }

        let scale = maxPixelDimension / longestSide
        let targetSize = CGSize(width: size.width * scale, height: size.height * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1

        return UIGraphicsImageRenderer(size: targetSize, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: targetSize))
        }
    }
}
