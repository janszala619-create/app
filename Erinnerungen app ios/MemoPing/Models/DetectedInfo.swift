import Foundation

struct DetectedInfo: Codable, Equatable {
    var dates: [Date] = []
    var dateStrings: [String] = []
    var phoneNumbers: [String] = []
    var urls: [String] = []
    var addresses: [String] = []

    var isEmpty: Bool {
        dates.isEmpty && dateStrings.isEmpty && phoneNumbers.isEmpty && urls.isEmpty && addresses.isEmpty
    }

    mutating func merge(_ other: DetectedInfo) {
        for (index, date) in other.dates.enumerated() where !dates.contains(where: { abs($0.timeIntervalSince(date)) < 60 }) {
            let dateString = other.dateStrings[safe: index] ?? formattedDate(date)
            dates.append(date)
            dateStrings.appendUnique(dateString)
        }

        dateStrings.appendUnique(contentsOf: other.dateStrings)
        phoneNumbers.appendUnique(contentsOf: other.phoneNumbers)
        urls.appendUnique(contentsOf: other.urls)
        addresses.appendUnique(contentsOf: other.addresses)
        sortDatesAndStrings()
    }

    func formattedDates() -> [String] {
        if !dateStrings.isEmpty {
            return dateStrings
        }

        return dates.map(formattedDate)
    }

    func sanitized() -> DetectedInfo {
        var info = DetectedInfo()
        info.dates = dates
        info.dateStrings = dateStrings.cleanedUniqueStrings()
        info.phoneNumbers = phoneNumbers.cleanedUniqueStrings { $0.filter { character in character.isNumber || character == "+" } }
        info.urls = urls.cleanedUniqueStrings {
            $0.lowercased()
                .replacingOccurrences(of: "https://", with: "")
                .replacingOccurrences(of: "http://", with: "")
                .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        }
        info.addresses = addresses.cleanedUniqueStrings { $0.lowercased() }
        info.sortDatesAndStrings()
        return info
    }

    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private mutating func sortDatesAndStrings() {
        let pairs = dates.enumerated()
            .map { index, date in
                (date: date, text: dateStrings[safe: index] ?? formattedDate(date))
            }
            .sorted { $0.date < $1.date }

        dates = pairs.map(\.date)
        let sortedDateStrings = pairs.map(\.text).filter { !$0.isEmpty }
        let additionalDateStrings = dateStrings.filter { dateString in
            !sortedDateStrings.contains(dateString)
        }
        dateStrings = sortedDateStrings + additionalDateStrings
    }
}

private extension Array where Element: Equatable {
    mutating func appendUnique(_ value: Element) {
        if !contains(value) {
            append(value)
        }
    }

    mutating func appendUnique(contentsOf values: [Element]) {
        for value in values where !contains(value) {
            append(value)
        }
    }
}

// Auch von DataDetectionService und PreviewViewModel genutzt —
// vorher lag diese Extension als private Kopie in vier Dateien.
extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

private extension Array where Element == String {
    func cleanedUniqueStrings(key: (String) -> String = { $0 }) -> [String] {
        var seenKeys = Set<String>()
        var values: [String] = []

        for value in self {
            let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
            let dedupKey = key(trimmedValue)
            guard !trimmedValue.isEmpty, !dedupKey.isEmpty, !seenKeys.contains(dedupKey) else {
                continue
            }

            seenKeys.insert(dedupKey)
            values.append(trimmedValue)
        }

        return values
    }
}
