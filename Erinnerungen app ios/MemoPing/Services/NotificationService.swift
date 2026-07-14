import Foundation
import UserNotifications

enum NotificationServiceError: LocalizedError {
    case permissionDenied
    case missingReminderDate
    case dateInPast
    case leadDateInPast
    case schedulingFailed(String)

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Benachrichtigungen sind nicht erlaubt. Du kannst sie in den Einstellungen aktivieren."
        case .missingReminderDate:
            return "Bitte wähle ein Datum und eine Uhrzeit für die Erinnerung."
        case .dateInPast:
            return "Der Erinnerungstermin muss in der Zukunft liegen."
        case .leadDateInPast:
            return "Die Vorab-Erinnerung liegt bereits in der Vergangenheit. Wähle eine kürzere Vorankündigung oder einen späteren Termin."
        case .schedulingFailed(let message):
            return "Die Erinnerung konnte nicht geplant werden: \(message)"
        }
    }
}

final class NotificationService {
    static let shared = NotificationService()

    private let center = UNUserNotificationCenter.current()

    private init() {}

    func requestAuthorization() async throws -> Bool {
        try await center.requestAuthorization(options: [.alert, .sound, .badge])
    }

    func getAuthorizationStatus() async -> UNAuthorizationStatus {
        let settings = await center.notificationSettings()
        return settings.authorizationStatus
    }

    func scheduleReminder(for memo: MemoItem) async throws {
        guard memo.hasReminder else {
            cancelReminder(for: memo)
            return
        }

        guard let reminderDate = memo.reminderDate else {
            throw NotificationServiceError.missingReminderDate
        }

        guard memo.reminderRepeatRule.isRepeating || reminderDate > Date() else {
            throw NotificationServiceError.dateInPast
        }

        guard try await ensureAuthorization() else {
            throw NotificationServiceError.permissionDenied
        }

        let mainRequest = try notificationRequest(
            identifier: memo.notificationIdentifier,
            title: memo.title.trimmed.isEmpty ? "RemindlyAi" : memo.title,
            body: notificationBody(for: memo),
            memo: memo,
            reminderDate: reminderDate
        )

        let leadRequest = try leadNotificationRequest(for: memo, reminderDate: reminderDate)
        let requests = [mainRequest, leadRequest].compactMap { $0 }

        guard !requests.isEmpty else {
            throw NotificationServiceError.schedulingFailed("Für diese Wiederholung konnte kein nächster Termin ermittelt werden.")
        }

        cancelReminder(for: memo)
        do {
            for request in requests {
                try await center.add(request)
            }
        } catch {
            removeNotifications(for: memo.id)
            throw NotificationServiceError.schedulingFailed(error.localizedDescription)
        }
    }

    func cancelReminder(for memo: MemoItem) {
        cancelReminder(with: memo.id)
    }

    func cancelReminder(with id: UUID) {
        removeNotifications(for: id)
    }

    /// Entfernt geplante Benachrichtigungen, die zu keinem aktiven Memo mehr gehören —
    /// z. B. von gelöschten oder erledigten Memos. `validIdentifiers` sind die UUID-Strings
    /// aller Memos, deren Erinnerungen weiterlaufen dürfen.
    func removeOrphanedNotifications(validIdentifiers: Set<String>) async {
        let pendingRequests = await center.pendingNotificationRequests()

        let orphanedIdentifiers = pendingRequests
            .map(\.identifier)
            .filter { identifier in
                guard !identifier.hasPrefix("debug-") else {
                    return false
                }

                let baseIdentifier = identifier.hasSuffix("-lead")
                    ? String(identifier.dropLast("-lead".count))
                    : identifier

                return !validIdentifiers.contains(baseIdentifier)
            }

        guard !orphanedIdentifiers.isEmpty else {
            return
        }

        center.removePendingNotificationRequests(withIdentifiers: orphanedIdentifiers)
        center.removeDeliveredNotifications(withIdentifiers: orphanedIdentifiers)
    }

    #if DEBUG
    func scheduleDebugReminder() async throws {
        guard try await ensureAuthorization() else {
            throw NotificationServiceError.permissionDenied
        }

        let content = UNMutableNotificationContent()
        content.title = "RemindlyAi Test"
        content.body = "Diese Test-Erinnerung wurde lokal in 10 Sekunden geplant."
        content.sound = .default
        content.userInfo = ["debug": true]

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 10, repeats: false)
        let request = UNNotificationRequest(
            identifier: "debug-\(UUID().uuidString)",
            content: content,
            trigger: trigger
        )

        try await center.add(request)
    }
    #endif

    static func statusText(for status: UNAuthorizationStatus) -> String {
        switch status {
        case .authorized:
            return "Erlaubt"
        case .denied:
            return "Nicht erlaubt"
        case .notDetermined:
            return "Noch nicht gefragt"
        case .provisional, .ephemeral:
            return "Eingeschränkt / unbekannt"
        @unknown default:
            return "Eingeschränkt / unbekannt"
        }
    }

    private func ensureAuthorization() async throws -> Bool {
        let status = await getAuthorizationStatus()

        switch status {
        case .authorized, .provisional, .ephemeral:
            return true
        case .notDetermined:
            return try await requestAuthorization()
        case .denied:
            return false
        @unknown default:
            return false
        }
    }

    private func notificationBody(for memo: MemoItem) -> String {
        let text = memo.previewText.trimmed.isEmpty ? "Erinnerung aus RemindlyAi" : memo.previewText.trimmed

        guard text.count > 120 else {
            return text
        }

        let endIndex = text.index(text.startIndex, offsetBy: 120)
        return String(text[..<endIndex]) + "..."
    }

    private func notificationRequest(
        identifier: String,
        title: String,
        body: String,
        memo: MemoItem,
        reminderDate: Date
    ) throws -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.userInfo = ["memoID": memo.id.uuidString]

        let trigger = calendarTrigger(for: memo, reminderDate: reminderDate)
        guard trigger.nextTriggerDate() != nil else {
            throw NotificationServiceError.schedulingFailed("Für diese Wiederholung konnte kein nächster Termin ermittelt werden.")
        }

        return UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
    }

    private func leadNotificationRequest(for memo: MemoItem, reminderDate: Date) throws -> UNNotificationRequest? {
        let leadTime = memo.reminderLeadTime
        guard leadTime.hasLeadNotification else {
            return nil
        }

        let leadDate = reminderDate.addingTimeInterval(-leadTime.timeInterval)
        if !memo.reminderRepeatRule.isRepeating && leadDate <= Date() {
            throw NotificationServiceError.leadDateInPast
        }

        let title = memo.title.trimmed.isEmpty ? "RemindlyAi Erinnerung" : "Bald: \(memo.title)"
        let body = "\(leadTime.shortDisplayName): \(notificationBody(for: memo))"

        return try notificationRequest(
            identifier: memo.leadNotificationIdentifier,
            title: title,
            body: body,
            memo: memo,
            reminderDate: leadDate
        )
    }

    private func removeNotifications(for id: UUID) {
        let identifiers = [id.uuidString, "\(id.uuidString)-lead"]
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
        center.removeDeliveredNotifications(withIdentifiers: identifiers)
    }

    private func calendarTrigger(for memo: MemoItem, reminderDate: Date) -> UNCalendarNotificationTrigger {
        let calendar = Calendar.current
        let components: DateComponents

        switch memo.reminderRepeatRule {
        case .none:
            components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: reminderDate)
        case .daily:
            components = calendar.dateComponents([.hour, .minute], from: reminderDate)
        case .weekly:
            components = calendar.dateComponents([.weekday, .hour, .minute], from: reminderDate)
        case .monthly:
            components = calendar.dateComponents([.day, .hour, .minute], from: reminderDate)
        case .yearly:
            components = calendar.dateComponents([.month, .day, .hour, .minute], from: reminderDate)
        }

        return UNCalendarNotificationTrigger(
            dateMatching: components,
            repeats: memo.reminderRepeatRule.isRepeating
        )
    }
}
