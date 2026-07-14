# RemindlyAi

RemindlyAi ist eine private iOS-App zum schnellen Erfassen von Notizen, Erinnerungen, Spracheingaben und Bildern. Die App ist fuer iOS 17+ ausgelegt und nutzt ausschliesslich Apple-Frameworks.

## Datenschutz

- Kein Login
- Kein Backend
- Keine Firebase- oder KI-API
- SwiftData speichert Memo-Daten in der aktuellen unsigned IPA lokal auf dem Geraet
- Bilder werden als Dateien lokal in `Application Support/MemoPingImages` gespeichert und in dieser Version nicht zwischen Geraeten synchronisiert
- Spracherkennung laeuft mit `requiresOnDeviceRecognition` lokal auf dem Geraet, sofern iOS On-Device-Erkennung fuer Deutsch unterstuetzt

## Projekt starten

1. Oeffne `MemoPing.xcodeproj` in Xcode.
2. Waehle das Target `MemoPing`.
3. Setze bei Bedarf unter "Signing & Capabilities" dein Apple-Team.
4. Setze einen echten Bundle Identifier, falls du die App signiert auf einem Geraet testen willst.
5. Starte die App auf einem iPhone oder Simulator mit iOS 17 oder neuer.

## iCloud/CloudKit Status

- CloudKit ist im Projekt vorbereitet, aber in der aktuellen unsigned GitHub-IPA bewusst nicht aktiv.
- Die IPA nutzt lokalen SwiftData-Speicher, damit die App ohne signierte iCloud-Entitlements stabil oeffnet.
- Die Einstellungen fragen CloudKit in der unsigned IPA nicht direkt ab.
- Lokale Bilddateien bleiben auf dem jeweiligen Geraet.
- Lokale Benachrichtigungen bleiben pro Geraet und werden nicht ueber iCloud synchronisiert.
- CloudKit-Sync sollte erst in einem signierten Xcode-Build mit echter Apple Team ID, Bundle Identifier und aktivierter iCloud/CloudKit Capability wieder aktiviert und getestet werden.

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

## Bekannte Limitierungen (unsigned IPA / Sideloadly)

- Die App Group `group.com.example.MemoPing` (Widget-Datenaustausch) funktioniert erst, wenn beim Signieren mit Sideloadly bzw. Xcode eine App-Group-ID des eigenen Teams eingetragen wird. Ohne gueltige App Group zeigt das Widget keine Daten.
- CloudKit-Entitlements sind vorbereitet, aber ohne signierten Build mit echter Team ID wirkungslos (siehe iCloud/CloudKit Status oben).
- Kalendertermine erhalten eine `memoping://`-URL; ein URL-Scheme ist dafuer nicht registriert, der Link in der Kalender-App oeffnet die App daher nicht.
- `requestRecordPermission` ist ab iOS 17 deprecated (Nachfolger: `AVAudioApplication`) — aktuell nur eine Compiler-Warnung.

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
