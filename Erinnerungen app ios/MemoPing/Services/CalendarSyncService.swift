import EventKit
import Foundation

enum CalendarSyncServiceError: LocalizedError {
    case permissionDenied
    case missingReminderDate
    case noWritableCalendar
    case saveFailed(String)

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Kalenderzugriff ist nicht erlaubt. Aktiviere den Zugriff in den Einstellungen, um Termine mit dem iOS-Kalender zu synchronisieren."
        case .missingReminderDate:
            return "Für die Kalender-Synchronisation wird ein Erinnerungstermin benötigt."
        case .noWritableCalendar:
            return "Es wurde kein beschreibbarer Kalender gefunden."
        case .saveFailed(let message):
            return "Der Kalendertermin konnte nicht synchronisiert werden: \(message)"
        }
    }
}

@MainActor
final class CalendarSyncService {
    static let shared = CalendarSyncService()

    private let eventStore = EKEventStore()

    private init() {}

    func authorizationStatus() -> EKAuthorizationStatus {
        EKEventStore.authorizationStatus(for: .event)
    }

    func requestAccess() async throws -> Bool {
        let status = authorizationStatus()
        if hasFullAccess(status) {
            return true
        }

        if #available(iOS 17.0, *) {
            return try await eventStore.requestFullAccessToEvents()
        }

        return try await withCheckedThrowingContinuation { continuation in
            eventStore.requestAccess(to: .event) { granted, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: granted)
                }
            }
        }
    }

    func saveEvent(for memo: MemoItem) async throws -> String {
        guard let reminderDate = memo.reminderDate else {
            throw CalendarSyncServiceError.missingReminderDate
        }

        guard try await ensureFullAccess() else {
            throw CalendarSyncServiceError.permissionDenied
        }

        let event = existingEvent(with: memo.calendarEventIdentifier) ?? EKEvent(eventStore: eventStore)
        event.calendar = event.calendar ?? eventStore.defaultCalendarForNewEvents

        guard event.calendar != nil else {
            throw CalendarSyncServiceError.noWritableCalendar
        }

        event.title = memo.title.trimmed.isEmpty ? "MemoPing" : memo.title
        event.startDate = reminderDate
        event.endDate = reminderDate.addingTimeInterval(30 * 60)
        event.notes = calendarNotes(for: memo)
        event.url = URL(string: "memoping://memo/\(memo.id.uuidString)")
        event.recurrenceRules = recurrenceRules(for: memo.reminderRepeatRule)
        event.alarms = alarms(for: memo)

        do {
            try eventStore.save(event, span: .futureEvents, commit: true)
            return event.eventIdentifier
        } catch {
            throw CalendarSyncServiceError.saveFailed(error.localizedDescription)
        }
    }

    func deleteEvent(with identifier: String?) async throws {
        guard let identifier,
              !identifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }

        guard try await ensureFullAccess() else {
            throw CalendarSyncServiceError.permissionDenied
        }

        guard let event = eventStore.event(withIdentifier: identifier) else {
            return
        }

        do {
            try eventStore.remove(event, span: .futureEvents, commit: true)
        } catch {
            throw CalendarSyncServiceError.saveFailed(error.localizedDescription)
        }
    }

    static func statusText(for status: EKAuthorizationStatus) -> String {
        switch status {
        case .notDetermined:
            return "Noch nicht gefragt"
        case .restricted:
            return "Eingeschränkt"
        case .denied:
            return "Nicht erlaubt"
        case .authorized:
            return "Erlaubt"
        case .fullAccess:
            return "Erlaubt"
        case .writeOnly:
            return "Nur Schreiben"
        @unknown default:
            return "Unbekannt"
        }
    }

    private func ensureFullAccess() async throws -> Bool {
        let status = authorizationStatus()
        if hasFullAccess(status) {
            return true
        }

        guard status == .notDetermined else {
            return false
        }

        return try await requestAccess()
    }

    private func hasFullAccess(_ status: EKAuthorizationStatus) -> Bool {
        switch status {
        case .authorized, .fullAccess:
            return true
        default:
            return false
        }
    }

    private func existingEvent(with identifier: String?) -> EKEvent? {
        guard let identifier,
              !identifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        return eventStore.event(withIdentifier: identifier)
    }

    private func calendarNotes(for memo: MemoItem) -> String {
        [
            memo.bodyText.trimmed,
            memo.recognizedText.trimmed
        ]
        .filter { !$0.isEmpty }
        .joined(separator: "\n\n")
    }

    private func recurrenceRules(for repeatRule: MemoReminderRepeatRule) -> [EKRecurrenceRule]? {
        let frequency: EKRecurrenceFrequency

        switch repeatRule {
        case .none:
            return nil
        case .daily:
            frequency = .daily
        case .weekly:
            frequency = .weekly
        case .monthly:
            frequency = .monthly
        case .yearly:
            frequency = .yearly
        }

        return [
            EKRecurrenceRule(
                recurrenceWith: frequency,
                interval: 1,
                end: nil
            )
        ]
    }

    private func alarms(for memo: MemoItem) -> [EKAlarm] {
        var alarms = [EKAlarm(relativeOffset: 0)]

        if memo.reminderLeadTime.hasLeadNotification {
            alarms.append(EKAlarm(relativeOffset: -memo.reminderLeadTime.timeInterval))
        }

        return alarms
    }
}
