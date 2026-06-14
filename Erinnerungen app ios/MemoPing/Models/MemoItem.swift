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

@Model
final class MemoItem {
    @Attribute(.unique) var id: UUID
    var title: String
    var bodyText: String
    var recognizedText: String
    var createdAt: Date
    var updatedAt: Date
    var reminderDate: Date?
    var hasReminder: Bool
    var reminderRepeatRawValue: String?
    var isCompleted: Bool
    var priorityRawValue: String
    var categoryRawValue: String?
    var sourceTypeRawValue: String
    var imageFileNames: [String]
    var detectedPhoneNumbers: [String]
    var detectedURLs: [String]
    var detectedAddresses: [String]
    var detectedDateStrings: [String]

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
        isCompleted: Bool = false,
        priority: MemoPriority = .normal,
        category: MemoCategory? = nil,
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
        self.isCompleted = isCompleted
        self.priorityRawValue = priority.rawValue
        self.categoryRawValue = category?.rawValue
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

    var reminderRepeatRule: MemoReminderRepeatRule {
        get {
            guard let reminderRepeatRawValue else {
                return .none
            }

            return MemoReminderRepeatRule(rawValue: reminderRepeatRawValue) ?? .none
        }
        set { reminderRepeatRawValue = newValue.rawValue }
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
