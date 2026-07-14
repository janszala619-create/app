import Foundation
import SwiftData
import WidgetKit

enum MemoWidgetSnapshotUpdater {
    /// Lädt alle Memos aus dem Model-Kontext und aktualisiert den Widget-Snapshot.
    /// Muss nach jeder Änderung an Memos aufgerufen werden, damit das Widget synchron bleibt.
    @MainActor
    static func refresh(in modelContext: ModelContext) {
        let descriptor = FetchDescriptor<MemoItem>()
        let items = (try? modelContext.fetch(descriptor)) ?? []
        update(from: items)
    }

    static func update(from items: [MemoItem]) {
        let calendar = Calendar.current
        let now = Date()

        let reminders = items
            .compactMap { item -> MemoWidgetReminderSnapshot? in
                guard item.hasReminder, !item.isCompleted,
                      let dueDate = todaysOccurrence(for: item, calendar: calendar, now: now) else {
                    return nil
                }

                return MemoWidgetReminderSnapshot(
                    id: item.id.uuidString,
                    title: item.title.isEmpty ? "Ohne Titel" : item.title,
                    dueDate: dueDate,
                    isCompleted: item.isCompleted
                )
            }
            .sorted { $0.dueDate < $1.dueDate }

        MemoWidgetSnapshotStore.save(
            MemoWidgetSnapshot(generatedAt: now, reminders: reminders)
        )
        WidgetCenter.shared.reloadTimelines(ofKind: MemoPingWidgetConstants.todayReminderKind)
    }

    /// Liefert den heutigen Termin eines Memos oder nil, wenn es heute nicht fällig ist.
    /// Wiederholende Erinnerungen werden auf ihr heutiges Vorkommen umgerechnet,
    /// damit z. B. eine tägliche Erinnerung von letzter Woche weiterhin im Widget erscheint.
    private static func todaysOccurrence(for item: MemoItem, calendar: Calendar, now: Date) -> Date? {
        guard let reminderDate = item.reminderDate else {
            return nil
        }

        let components: DateComponents

        switch item.reminderRepeatRule {
        case .none:
            return calendar.isDateInToday(reminderDate) ? reminderDate : nil
        case .daily:
            components = calendar.dateComponents([.hour, .minute], from: reminderDate)
        case .weekly:
            components = calendar.dateComponents([.weekday, .hour, .minute], from: reminderDate)
        case .monthly:
            components = calendar.dateComponents([.day, .hour, .minute], from: reminderDate)
        case .yearly:
            components = calendar.dateComponents([.month, .day, .hour, .minute], from: reminderDate)
        }

        // Serie erst ab ihrem Startdatum anzeigen
        let startOfToday = calendar.startOfDay(for: now)
        guard calendar.startOfDay(for: reminderDate) <= startOfToday else {
            return nil
        }

        guard let occurrence = calendar.nextDate(
            after: startOfToday.addingTimeInterval(-1),
            matching: components,
            matchingPolicy: .nextTime
        ), calendar.isDateInToday(occurrence) else {
            return nil
        }

        return occurrence
    }
}
