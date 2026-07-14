# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Projekt

RemindlyAI/MemoPing — deutschsprachige iOS-Reminder-/Memo-App (SwiftUI, MVVM, SwiftData, iOS 17+, Swift 5). Kein Backend, kein Login; alle Daten lokal. Das Xcode-Projekt liegt unter `Erinnerungen app ios/MemoPing.xcodeproj` — **der Ordnername enthält Leerzeichen, Pfade immer quoten**.

## Build & Verifikation

Es gibt kein Test-Target. Verifikation läuft über Kompilieren + manuelles Testen auf dem Gerät.

```bash
# Auf diesem Mac liegt Xcode nicht in /Applications:
export DEVELOPER_DIR="/Users/jan/Desktop/Xcode.app/Contents/Developer"

# Voller Build ohne Signierung (wie in CI)
xcodebuild -project "Erinnerungen app ios/MemoPing.xcodeproj" -scheme MemoPing \
  -configuration Release -sdk iphoneos -destination "generic/platform=iOS" \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" build

# Schneller Syntax-Check einer Datei (kein Typecheck, braucht kein Xcode)
xcrun swiftc -parse "Erinnerungen app ios/MemoPing/Views/DetailView.swift"
```

Foundation-only-Dateien (`DataDetectionService`, `DetectedInfo`) lassen sich als macOS-Binary kompilieren und mit einem kleinen `main.swift` funktional testen — einzige Abhängigkeit ist ein Shim für die `String.trimmed`-Extension (definiert in `CaptureViewModel.swift`).

## Deployment

- **Unsigned IPA** via GitHub Actions (`.github/workflows/build-ios.yml`, läuft bei Push auf `main`), Installation per Sideloadly. Kein Apple Developer Account — der CI-Build ist die verbindliche Build-Verifikation.
- Deshalb funktionieren App Group (`group.com.example.MemoPing`, Widget-Datenaustausch) und CloudKit nur nach Anpassung an eine eigene Team-ID beim Signieren; `ICloudSyncService` ist bewusst ein Stub, SwiftData speichert rein lokal (Details: README „Bekannte Limitierungen").
- Neue Swift-Dateien müssen manuell in `project.pbxproj` registriert werden (handgeschriebene IDs `AAF0…`). Wenn möglich, Code in bestehende Dateien einfügen — insbesondere Shared-Code in `MemoPing/Shared/MemoWidgetSnapshotStore.swift`, die einzige Datei, die in **beiden** Targets (App + Widget) kompiliert wird.

## Architektur

**Haupt-Flow:** `CaptureView`/`CaptureViewModel` (Text/Diktat/Bild erfassen) → `PreviewView`/`PreviewViewModel` (Titel, Erinnerung, Kategorie, Speichern) → `HomeView` (Dashboard mit Sektionen aus `HomeViewModel.sectionGroups`) → `DetailView` (Anzeigen/Bearbeiten). Übergabe Capture→Preview per `MemoDraft`; darin trägt `MemoDraftImage.recognizedText` bereits erkannten OCR-Text (nil = ausstehend, "" = kein Treffer), damit die Vorschau OCR nicht wiederholt.

**Persistenz:** Zwei `@Model`-Klassen: `MemoItem` und `MemoCategoryItem` (Container-Singleton `MemoDataStore`). `MemoItem` speichert Enums als rawValue-Strings mit computed-Property-Accessoren und hat für alle Properties Defaults (CloudKit-kompatibel gehalten). Kategorien: `MemoCategoryItem.id` ist bei den Seed-Kategorien der rawValue des Legacy-Enums `MemoCategory` — `MemoCategoryItem.item(for:in:)` löst beide Welten auf; `memoItem.categoryRawValue` referenziert diese id.

**Bilder** liegen als JPEG-Dateien in `Application Support/MemoPingImages` (`ImageStorageService`), Memos referenzieren nur Dateinamen. Die Vorschau speichert Dateien **vor** dem Memo-Save; Aufräumen läuft über die Discard-Pfade der PreviewViewModel plus einen Orphan-Sweep beim App-Start (`HomeView.task`, 24-h-Schonfrist). Views laden Bilder asynchron als ImageIO-Thumbnails, nie synchron im View-Body.

**Invariante bei jeder Memo-Mutation** (anlegen, erledigen, snoozen, löschen, bearbeiten): (1) explizit `modelContext.save()`, (2) `MemoWidgetSnapshotUpdater.refresh(in:)` für das Widget, (3) `NotificationService` (Haupt- + `-lead`-Notification, Identifier = Memo-UUID) und — falls `syncsToCalendar` — `CalendarSyncService` (`saveEvent` aktualisiert bestehende Events über `calendarEventIdentifier`) synchron halten. Diese Logik existiert derzeit mehrfach parallel in `HomeView`, `DetailView` und `MemoPingAppIntents` — bei Änderungen alle Pfade prüfen.

**Widget-Pipeline:** App schreibt `MemoWidgetSnapshot` als JSON in die App-Group-UserDefaults (`MemoWidgetSnapshotStore`), Widget liest ihn und filtert beim Rendern erneut auf „heute + offen". AppIntents erzeugen eigene `ModelContext`-Instanzen aus dem geteilten Container.

## Konventionen

- UI-Texte sind durchgehend hartkodiert deutsch (keine Lokalisierung). Datumsanzeigen laufen über `Date.germanFormatted(date:time:)` (in `MemoWidgetSnapshotStore.swift`), nie über locale-abhängiges `.formatted(date:time:)`.
- Die App erzwingt Dark Mode (`AppRootView`), nutzt aber System-Farben (`secondarySystemGroupedBackground` etc.) und Karten-Layouts mit per-View `detailCard()`/`settingsCard()`-Extensions.
- Fehler laufen in allen Views über ein `errorMessage: String?`-State + `alert("Hinweis", …)`-Muster mit `errorBinding`.
- Services sind Singletons (`shared`); `SpeechRecognitionService` ist die Ausnahme (Instanz pro CaptureViewModel, @MainActor, de-DE, On-Device-Erkennung wenn verfügbar).
