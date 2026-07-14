import AppIntents
import Foundation
import SwiftData

struct ReminderEntity: AppEntity, Identifiable {
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Erinnerung")
    static var defaultQuery = ReminderEntityQuery()

    let id: String
    let title: String
    let dueText: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(title)",
            subtitle: "\(dueText)"
        )
    }
}

struct ReminderEntityQuery: EntityQuery {
    @MainActor
    func entities(for identifiers: [ReminderEntity.ID]) async throws -> [ReminderEntity] {
        MemoIntentDataProvider.reminderEntities()
            .filter { identifiers.contains($0.id) }
    }

    @MainActor
    func suggestedEntities() async throws -> [ReminderEntity] {
        MemoIntentDataProvider.reminderEntities(limit: 8)
    }
}

struct QuickCaptureIntent: AppIntent {
    static var title: LocalizedStringResource = "Schnell erfassen"
    static var description = IntentDescription("Öffnet RemindlyAi direkt zum Erfassen eines neuen Memos.")
    static var openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        CaptureRequestCenter.shared.requestCapture()
        return .result()
    }
}

struct TodaysRemindersIntent: AppIntent {
    static var title: LocalizedStringResource = "Heutige Erinnerungen anzeigen"
    static var description = IntentDescription("Zeigt die offenen Erinnerungen für heute als Kurzliste.")

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let summary = MemoIntentDataProvider.todaysReminderSummary()
        return .result(value: summary)
    }
}

struct CompleteReminderIntent: AppIntent {
    static var title: LocalizedStringResource = "Erinnerung abhaken"
    static var description = IntentDescription("Markiert eine ausgewählte Erinnerung als erledigt.")

    @Parameter(title: "Erinnerung")
    var reminder: ReminderEntity

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let result = try await MemoIntentDataProvider.completeReminder(with: reminder.id)
        return .result(value: result)
    }
}

struct MemoPingAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: QuickCaptureIntent(),
            phrases: [
                "Schnell erfassen in \(.applicationName)",
                "Neues Memo in \(.applicationName)"
            ],
            shortTitle: "Schnell erfassen",
            systemImageName: "plus.circle"
        )

        AppShortcut(
            intent: TodaysRemindersIntent(),
            phrases: [
                "Heutige Erinnerungen in \(.applicationName)",
                "Was steht heute in \(.applicationName) an"
            ],
            shortTitle: "Heute",
            systemImageName: "calendar"
        )

        AppShortcut(
            intent: CompleteReminderIntent(),
            phrases: [
                "Erinnerung abhaken in \(.applicationName)",
                "Memo in \(.applicationName) erledigen"
            ],
            shortTitle: "Abhaken",
            systemImageName: "checkmark.circle"
        )
    }
}

enum MemoIntentDataProvider {
    @MainActor
    static func reminderEntities(limit: Int? = nil) -> [ReminderEntity] {
        let items = activeReminderItems()
            .sorted { lhs, rhs in
                (lhs.reminderDate ?? .distantFuture) < (rhs.reminderDate ?? .distantFuture)
            }

        let limitedItems = limit.map { Array(items.prefix($0)) } ?? items
        return limitedItems.map(entity)
    }

    @MainActor
    static func todaysReminderSummary() -> String {
        let items = activeReminderItems()
            .filter { item in
                guard let reminderDate = item.reminderDate else {
                    return false
                }

                return Calendar.current.isDateInToday(reminderDate)
            }
            .sorted { lhs, rhs in
                (lhs.reminderDate ?? .distantFuture) < (rhs.reminderDate ?? .distantFuture)
            }

        guard !items.isEmpty else {
            return "Heute sind keine offenen Erinnerungen geplant."
        }

        return items
            .prefix(6)
            .map { item in
                let time = item.reminderDate?.germanFormatted(date: .omitted, time: .shortened) ?? "ohne Uhrzeit"
                return "\(time): \(item.title)"
            }
            .joined(separator: "\n")
    }

    @MainActor
    static func completeReminder(with id: String) async throws -> String {
        let context = ModelContext(MemoDataStore.shared.container)
        let descriptor = FetchDescriptor<MemoItem>()
        let items = try context.fetch(descriptor)

        guard let item = items.first(where: { $0.id.uuidString == id }) else {
            return "Diese Erinnerung wurde nicht gefunden."
        }

        try await MemoActionService.shared.setCompleted(true, for: item, in: context)

        return "Erledigt markiert: \(item.title)"
    }

    @MainActor
    private static func activeReminderItems() -> [MemoItem] {
        let context = ModelContext(MemoDataStore.shared.container)
        let descriptor = FetchDescriptor<MemoItem>(
            predicate: #Predicate<MemoItem> { $0.hasReminder && !$0.isCompleted && $0.reminderDate != nil }
        )

        do {
            return try context.fetch(descriptor)
        } catch {
            return []
        }
    }

    private static func entity(from item: MemoItem) -> ReminderEntity {
        let dueText = item.reminderDate?.germanFormatted(date: .abbreviated, time: .shortened) ?? "ohne Termin"
        return ReminderEntity(
            id: item.id.uuidString,
            title: item.title.isEmpty ? "Ohne Titel" : item.title,
            dueText: dueText
        )
    }
}
