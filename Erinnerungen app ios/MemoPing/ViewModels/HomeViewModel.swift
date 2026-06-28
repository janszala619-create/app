import Combine
import Foundation

enum MemoListSection: String, CaseIterable, Identifiable {
    case today
    case upcoming
    case noReminder
    case completed

    var id: String { rawValue }

    var title: String {
        switch self {
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

    /// Compatibility bridge for views that still use the legacy enum-based category API.
    /// New code should prefer `selectedCategoryRawValue` so custom categories also work.
    var selectedCategory: MemoCategory? {
        get {
            guard let selectedCategoryRawValue else { return nil }
            return MemoCategory(rawValue: selectedCategoryRawValue)
        }
        set {
            selectedCategoryRawValue = newValue?.rawValue
        }
    }

    /// Compatibility overload for the current HomeView. It preserves the legacy default
    /// categories while the view is migrated to query `MemoCategoryItem` directly.
    func sectionGroups(from items: [MemoItem]) -> [MemoSectionGroup] {
        sectionGroups(from: items, categories: Self.legacyCategories)
    }

    func sectionGroups(from items: [MemoItem], categories: [MemoCategoryItem]) -> [MemoSectionGroup] {
        let filteredItems = filtered(items, categories: categories)
        let calendar = Calendar.current

        let today = filteredItems.filter { item in
            guard !item.isCompleted, item.hasReminder, let reminderDate = item.reminderDate else {
                return false
            }
            return calendar.isDateInToday(reminderDate)
        }

        let upcoming = filteredItems.filter { item in
            guard !item.isCompleted, item.hasReminder, let reminderDate = item.reminderDate else {
                return false
            }
            return !calendar.isDateInToday(reminderDate)
        }

        let noReminder = filteredItems.filter { item in
            !item.isCompleted && !item.hasReminder
        }

        let completed = filteredItems.filter(\.isCompleted)

        return [
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

    private static var legacyCategories: [MemoCategoryItem] {
        MemoCategory.allCases.enumerated().map { index, category in
            MemoCategoryItem(
                id: category.rawValue,
                name: category.displayName,
                systemImage: category.systemImage,
                tintRawValue: category.legacyTintRawValue,
                isDefault: true,
                sortOrder: index
            )
        }
    }
}

private extension MemoCategory {
    var legacyTintRawValue: String {
        switch self {
        case .uni:
            return "indigo"
        case .privat:
            return "green"
        case .wichtig:
            return "orange"
        case .dokumente:
            return "teal"
        case .ideen:
            return "yellow"
        }
    }
}
