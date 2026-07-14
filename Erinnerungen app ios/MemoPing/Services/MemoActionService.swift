import Foundation
import SwiftData

/// Zentralisiert Erledigen, Wiederöffnen und Löschen von Memos.
///
/// Diese Aktionen müssen Notification, Kalender-Event, Widget-Snapshot und
/// `modelContext.save()` gemeinsam synchron halten. Die Logik lag zuvor
/// mehrfach parallel in HomeView, DetailView und den AppIntents und
/// driftete dort subtil auseinander.
@MainActor
final class MemoActionService {
    static let shared = MemoActionService()

    private init() {}

    /// Markiert ein Memo als erledigt bzw. wieder offen. Beim Erledigen werden
    /// Notification und Kalender-Event beendet (sonst laufen deren Alarme und
    /// Wiederholungen endlos weiter), beim Wiederöffnen wird die Notification
    /// neu geplant. Bei Fehlern wird der Erledigt-Status zurückgerollt.
    func setCompleted(_ isCompleted: Bool, for item: MemoItem, in modelContext: ModelContext) async throws {
        let previousCompleted = item.isCompleted
        let previousUpdatedAt = item.updatedAt
        item.isCompleted = isCompleted
        item.updatedAt = Date()

        do {
            if isCompleted {
                NotificationService.shared.cancelReminder(for: item)
                await removeCalendarEvent(for: item)
            } else if item.hasReminder {
                try await NotificationService.shared.scheduleReminder(for: item)
            }
            try modelContext.save()
            MemoWidgetSnapshotUpdater.refresh(in: modelContext)
        } catch {
            item.isCompleted = previousCompleted
            item.updatedAt = previousUpdatedAt
            throw error
        }
    }

    /// Löscht ein Memo mitsamt Notification, Kalender-Event und Bilddateien.
    func delete(_ item: MemoItem, in modelContext: ModelContext) async throws {
        NotificationService.shared.cancelReminder(for: item)
        await removeCalendarEvent(for: item)
        ImageStorageService.shared.deleteImages(fileNames: item.imageFileNames)
        modelContext.delete(item)
        try modelContext.save()
        MemoWidgetSnapshotUpdater.refresh(in: modelContext)
    }

    /// Löscht den synchronisierten Kalendertermin, damit dessen Alarme und
    /// Wiederholungen nicht weiterlaufen, wenn die Erinnerung beendet wurde.
    func removeCalendarEvent(for item: MemoItem) async {
        guard let eventIdentifier = item.calendarEventIdentifier else { return }
        try? await CalendarSyncService.shared.deleteEvent(with: eventIdentifier)
        item.calendarEventIdentifier = nil
        item.syncsToCalendar = false
    }
}
