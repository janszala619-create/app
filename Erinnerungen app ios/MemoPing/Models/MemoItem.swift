import Foundation
import SwiftData

enum MemoReminderRepeatRule: String, CaseIterable, Codable, Identifiable {
    case none
    case daily
    case weekly
    case monthly
    case yearly

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .none:
            return "Einmalig"
        case .daily:
            return "Täglich"
        case .weekly:
            return "Wöchentlich"
        case .monthly:
            return "Monatlich"
        case .yearly:
            return "Jährlich"
        }
    }

    var systemImage: String {
        switch self {
        case .none:
            return "bell"
        case .daily:
            return "calendar.day.timeline.left"
        case .weekly:
            return "calendar.badge.clock"
        case .monthly:
            return "calendar"
        case .yearly:
            return "calendar.badge.exclamationmark"
        }
    }

    var isRepeating: Bool {
        self != .none
    }
}

enum MemoReminderLeadTime: String, CaseIterable, Codable, Identifiable {
    case none
    case minutes15
    case minutes30
    case hour1
    case hours5
    case day1
    case week1

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .none:
            return "Keine"
        case .minutes15:
            return "15 Minuten vorher"
        case .minutes30:
            return "30 Minuten vorher"
        case .hour1:
            return "1 Stunde vorher"
        case .hours5:
            return "5 Stunden vorher"
        case .day1:
            return "1 Tag vorher"
        case .week1:
            return "1 Woche vorher"
        }
    }

    var shortDisplayName: String {
        switch self {
        case .none:
            return "Keine"
        case .minutes15:
            return "15 Min. vorher"
        case .minutes30:
            return "30 Min. vorher"
        case .hour1:
            return "1 Std. vorher"
        case .hours5:
            return "5 Std. vorher"
        case .day1:
            return "1 Tag vorher"
        case .week1:
            return "1 Woche vorher"
        }
    }

    var systemImage: String {
        switch self {
        case .none:
            return "bell"
        case .minutes15, .minutes30:
            return "clock"
        case .hour1, .hours5:
            return "clock"
        case .day1, .week1:
            return "calendar"
        }
    }

    var timeInterval: TimeInterval {
        switch self {
        case .none:
            return 0
        case .minutes15:
            return 15 * 60
        case .minutes30:
            return 30 * 60
        case .hour1:
            return 60 * 60
        case .hours5:
            return 5 * 60 * 60
        case .day1:
            return 24 * 60 * 60
        case .week1:
            return 7 * 24 * 60 * 60
        }
    }

    var hasLeadNotification: Bool {
        self != .none
    }
}

@Model
final class MemoItem {
    var id: UUID = UUID()
    var title: String = ""
    var bodyText: String = ""
    var recognizedText: String = ""
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var reminderDate: Date?
    var hasReminder: Bool = false
    var reminderRepeatRawValue: String? = MemoReminderRepeatRule.none.rawValue
    var reminderLeadTimeRawValue: String? = MemoReminderLeadTime.none.rawValue
    var syncsToCalendar: Bool = false
    var calendarEventIdentifier: String?
    var isCompleted: Bool = false
    var priorityRawValue: String = MemoPriority.normal.rawValue
    var categoryRawValue: String?
    var sourceTypeRawValue: String = MemoSourceType.text.rawValue
    var imageFileNames: [String] = []
    var detectedPhoneNumbers: [String] = []
    var detectedURLs: [String] = []
    var detectedAddresses: [String] = []
    var detectedDateStrings: [String] = []

    init(
        id: UUID = UUID(),
        title: String,
        bodyText: String = "",
        recognizedText: String = "",
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        reminderDate: Date? = nil,
        hasReminder: Bool = false,
        reminderRepeatRule: MemoReminderRepeatRule = .none,
        reminderLeadTime: MemoReminderLeadTime = .none,
        syncsToCalendar: Bool = false,
        calendarEventIdentifier: String? = nil,
        isCompleted: Bool = false,
        priority: MemoPriority = .normal,
        category: MemoCategory? = nil,
        categoryRawValue: String? = nil,
        sourceType: MemoSourceType = .text,
        imageFileNames: [String] = [],
        detectedPhoneNumbers: [String] = [],
        detectedURLs: [String] = [],
        detectedAddresses: [String] = [],
        detectedDateStrings: [String] = []
    ) {
        self.id = id
        self.title = title
        self.bodyText = bodyText
        self.recognizedText = recognizedText
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.reminderDate = reminderDate
        self.hasReminder = hasReminder
        self.reminderRepeatRawValue = reminderRepeatRule.rawValue
        self.reminderLeadTimeRawValue = reminderLeadTime.rawValue
        self.syncsToCalendar = syncsToCalendar
        self.calendarEventIdentifier = calendarEventIdentifier
        self.isCompleted = isCompleted
        self.priorityRawValue = priority.rawValue
        self.categoryRawValue = categoryRawValue ?? category?.rawValue
        self.sourceTypeRawValue = sourceType.rawValue
        self.imageFileNames = imageFileNames
        self.detectedPhoneNumbers = detectedPhoneNumbers
        self.detectedURLs = detectedURLs
        self.detectedAddresses = detectedAddresses
        self.detectedDateStrings = detectedDateStrings
    }
}

extension MemoItem {
    var priority: MemoPriority {
        get { MemoPriority(rawValue: priorityRawValue) ?? .normal }
        set { priorityRawValue = newValue.rawValue }
    }

    var category: MemoCategory? {
        get {
            guard let categoryRawValue else { return nil }
            return MemoCategory(rawValue: categoryRawValue)
        }
        set { categoryRawValue = newValue?.rawValue }
    }

    var sourceType: MemoSourceType {
        get { MemoSourceType(rawValue: sourceTypeRawValue) ?? .text }
        set { sourceTypeRawValue = newValue.rawValue }
    }

    var notificationIdentifier: String {
        id.uuidString
    }

    var leadNotificationIdentifier: String {
        "\(id.uuidString)-lead"
    }

    var reminderRepeatRule: MemoReminderRepeatRule {
        get {
            guard let reminderRepeatRawValue else {
                return .none
            }

            return MemoReminderRepeatRule(rawValue: reminderRepeatRawValue) ?? .none
        }
        set { reminderRepeatRawValue = newValue.rawValue }
    }

    var reminderLeadTime: MemoReminderLeadTime {
        get {
            guard let reminderLeadTimeRawValue else {
                return .none
            }

            return MemoReminderLeadTime(rawValue: reminderLeadTimeRawValue) ?? .none
        }
        set { reminderLeadTimeRawValue = newValue.rawValue }
    }

    var previewText: String {
        let preferredText = bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? recognizedText : bodyText
        let compactText = preferredText.trimmingCharacters(in: .whitespacesAndNewlines)

        if compactText.isEmpty {
            return imageFileNames.isEmpty ? "Keine Vorschau" : "Bildnotiz"
        }

        if compactText.count <= 120 {
            return compactText
        }

        let endIndex = compactText.index(compactText.startIndex, offsetBy: 120)
        return String(compactText[..<endIndex]) + "..."
    }
}
