import Combine
import Foundation

enum MemoListSection: String, CaseIterable, Identifiable {
    case overdue
    case today
    case upcoming
    case noReminder
    case completed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overdue:
            return "Überfällig"
        case .today:
            return "Heute"
        case .upcoming:
            return "Kommend"
        case .noReminder:
            return "Ohne Erinnerung"
        case .completed:
            return "Erledigt"
        }
    }
}

struct MemoSectionGroup: Identifiable {
    let section: MemoListSection
    let items: [MemoItem]

    var id: MemoListSection { section }
}

@MainActor
final class HomeViewModel: ObservableObject {
    @Published var searchText = ""
    @Published var selectedCategoryRawValue: String?

    func sectionGroups(from items: [MemoItem], categories: [MemoCategoryItem]) -> [MemoSectionGroup] {
        let filteredItems = filtered(items, categories: categories)
        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: Date())

        let reminderItems = filteredItems.filter { item in
            !item.isCompleted && item.hasReminder && item.reminderDate != nil
        }

        // Einmalige Erinnerungen mit vergangenem Termin sind überfällig —
        // wiederholende laufen planmäßig weiter und zählen nicht als überfällig.
        let overdue = reminderItems.filter { item in
            guard let reminderDate = item.reminderDate else { return false }
            return reminderDate < startOfToday && !item.reminderRepeatRule.isRepeating
        }

        let today = reminderItems.filter { item in
            guard let reminderDate = item.reminderDate else { return false }
            return calendar.isDateInToday(reminderDate)
        }

        let upcoming = reminderItems.filter { item in
            guard let reminderDate = item.reminderDate else { return false }
            guard !calendar.isDateInToday(reminderDate) else { return false }
            return reminderDate >= startOfToday || item.reminderRepeatRule.isRepeating
        }

        let noReminder = filteredItems.filter { item in
            !item.isCompleted && !item.hasReminder
        }

        let completed = filteredItems.filter(\.isCompleted)

        return [
            MemoSectionGroup(section: .overdue, items: sorted(overdue)),
            MemoSectionGroup(section: .today, items: sorted(today)),
            MemoSectionGroup(section: .upcoming, items: sorted(upcoming)),
            MemoSectionGroup(section: .noReminder, items: sorted(noReminder)),
            MemoSectionGroup(section: .completed, items: sorted(completed))
        ].filter { !$0.items.isEmpty }
    }

    private func filtered(_ items: [MemoItem], categories: [MemoCategoryItem]) -> [MemoItem] {
        let normalizedSearch = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        return items.filter { item in
            let categoryMatches = selectedCategoryRawValue == nil || item.categoryRawValue == selectedCategoryRawValue

            guard categoryMatches else {
                return false
            }

            guard !normalizedSearch.isEmpty else {
                return true
            }

            let searchableText = [
                item.title,
                item.bodyText,
                item.recognizedText,
                MemoCategoryItem.item(for: item.categoryRawValue, in: categories)?.displayName ?? "",
                item.priority.displayName,
                item.detectedPhoneNumbers.joined(separator: " "),
                item.detectedURLs.joined(separator: " "),
                item.detectedAddresses.joined(separator: " "),
                item.detectedDateStrings.joined(separator: " ")
            ].joined(separator: " ").lowercased()

            return searchableText.contains(normalizedSearch)
        }
    }

    private func sorted(_ items: [MemoItem]) -> [MemoItem] {
        items.sorted { lhs, rhs in
            switch (lhs.reminderDate, rhs.reminderDate) {
            case let (lhsDate?, rhsDate?):
                return lhsDate < rhsDate
            case (.some, .none):
                return true
            case (.none, .some):
                return false
            case (.none, .none):
                return lhs.createdAt > rhs.createdAt
            }
        }
    }
}
