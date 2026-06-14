# MemoPing

MemoPing ist eine private iOS-App zum schnellen Erfassen von Notizen, Erinnerungen, Spracheingaben und Bildern. Die App ist fuer iOS 17+ ausgelegt und nutzt ausschliesslich Apple-Frameworks.

## Datenschutz

- Kein Login
- Kein Backend
- Keine Firebase- oder KI-API
- SwiftData speichert Memo-Daten lokal und synchronisiert sie ueber Apples iCloud/CloudKit, wenn iCloud verfuegbar ist
- Bilder werden als Dateien lokal in `Application Support/MemoPingImages` gespeichert und in dieser Version nicht zwischen Geraeten synchronisiert
- Spracherkennung wird mit `requiresOnDeviceRecognition = true` auf lokale Erkennung begrenzt

## Projekt starten

1. Oeffne `MemoPing.xcodeproj` in Xcode.
2. Waehle das Target `MemoPing`.
3. Setze bei Bedarf unter "Signing & Capabilities" dein Apple-Team.
4. Pruefe unter "Signing & Capabilities", dass iCloud mit CloudKit aktiv ist.
5. Setze einen echten Bundle Identifier. Der CloudKit-Container wird als `iCloud.<Bundle Identifier>` verwendet.
6. Starte die App auf einem iPhone oder Simulator mit iOS 17 oder neuer.

## iCloud/CloudKit Sync

- `MemoPing/MemoPing.entitlements` bereitet CloudKit fuer `iCloud.$(PRODUCT_BUNDLE_IDENTIFIER)` vor.
- `MemoPingApp` und die Einstellungen starten in der unsigned GitHub-IPA bewusst mit lokalem SwiftData-Speicher, damit die App ohne signierte iCloud-Entitlements stabil oeffnet.
- Synchronisiert werden Memo-Metadaten, Text, OCR-Text, Reminder-Daten, Wiederholungsregel, Kategorie, Prioritaet und erkannte Informationen.
- Lokale Bilddateien werden nicht automatisch durch CloudKit synchronisiert; nur die gespeicherten Dateinamen sind Teil des Memo-Datensatzes.
- Lokale Benachrichtigungen bleiben pro Geraet. Beim Anzeigen der Memo-Liste werden vorhandene Reminder-Daten wieder lokal geplant, sofern Benachrichtigungen erlaubt sind.

## Benoetigte Info.plist-Berechtigungen

Die Permission Strings sind bereits in `MemoPing/App/Info.plist` eingetragen:

- `NSMicrophoneUsageDescription`
- `NSSpeechRecognitionUsageDescription`
- `NSCameraUsageDescription`
- `NSPhotoLibraryUsageDescription`

## Simulator-Hinweise

- Kameraaufnahme ist im iOS Simulator normalerweise nicht verfuegbar.
- Lokale On-Device-Spracherkennung kann je nach Simulator, Sprache und macOS/Xcode-Konfiguration nicht verfuegbar sein.
- Bildauswahl, OCR, SwiftData und lokale Benachrichtigungen lassen sich im Simulator grundsaetzlich testen.

## Struktur

```text
MemoPing/
  App/
  Models/
  Views/
  ViewModels/
  Services/
  Components/
```

Die App nutzt SwiftUI, SwiftData, UserNotifications, Speech, Vision, PhotosUI und einen `UIImagePickerController`-Wrapper fuer Kameraaufnahmen.
