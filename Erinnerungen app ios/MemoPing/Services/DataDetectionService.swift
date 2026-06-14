import Foundation

final class DataDetectionService {
    static let shared = DataDetectionService()

    private let detector: NSDataDetector?
    private let maxCharactersToScan = 50_000

    init() {
        let checkingTypes: NSTextCheckingResult.CheckingType = [.date, .phoneNumber, .link, .address]
        detector = try? NSDataDetector(types: checkingTypes.rawValue)
    }

    func detect(in text: String) -> DetectedInfo {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let detector, !trimmedText.isEmpty else {
            return DetectedInfo()
        }

        let textToScan = String(trimmedText.prefix(maxCharactersToScan))
        let range = NSRange(textToScan.startIndex..<textToScan.endIndex, in: textToScan)
        let matches = detector.matches(in: textToScan, options: [], range: range)

        var info = DetectedInfo()

        for match in matches {
            guard let originalText = originalMatchText(for: match, in: textToScan) else {
                continue
            }

            if match.resultType.contains(.date), let date = match.date {
                info.appendDate(date, originalText: originalText)
            }

            if match.resultType.contains(.phoneNumber), let phoneNumber = match.phoneNumber {
                info.appendPhoneNumber(phoneNumber.trimmed.isEmpty ? originalText : phoneNumber)
            }

            if match.resultType.contains(.link), let urlString = urlString(from: match, originalText: originalText) {
                info.appendURL(urlString)
            }

            if match.resultType.contains(.address), let address = addressString(from: match, originalText: originalText) {
                info.appendAddress(address)
            }
        }

        appendPlainDomainLinks(from: textToScan, to: &info)
        return info
    }

    private func originalMatchText(for match: NSTextCheckingResult, in text: String) -> String? {
        guard let range = Range(match.range, in: text) else {
            return nil
        }

        let value = String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    private func urlString(from match: NSTextCheckingResult, originalText: String) -> String? {
        let value = (match.url?.absoluteString ?? originalText)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: ".,;:"))

        guard !value.isEmpty else {
            return nil
        }

        return value
    }

    private func addressString(from match: NSTextCheckingResult, originalText: String) -> String? {
        if let components = match.addressComponents {
            let orderedValues = [
                components[.street],
                components[.zip],
                components[.city],
                components[.state],
                components[.country]
            ]
                .compactMap { $0?.trimmed }
                .filter { !$0.isEmpty }

            if !orderedValues.isEmpty {
                return orderedValues.joined(separator: ", ")
            }
        }

        return originalText.trimmed.isEmpty ? nil : originalText
    }

    private func appendPlainDomainLinks(from text: String, to info: inout DetectedInfo) {
        let pattern = #"(?i)\b(?:mailto:[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,24}|(?:www\.)?[A-Z0-9-]+(?:\.[A-Z0-9-]+)*\.[A-Z]{2,24}(?::\d{2,5})?(?:/[^\s<>"']*)?)\b"#

        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return
        }

        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        for match in regex.matches(in: text, options: [], range: range) {
            guard let matchRange = Range(match.range, in: text) else {
                continue
            }

            let value = String(text[matchRange])
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: ".,;:"))

            guard !value.contains("@") || value.lowercased().hasPrefix("mailto:") else {
                continue
            }

            info.appendURL(value)
        }
    }
}

private extension DetectedInfo {
    mutating func appendDate(_ date: Date, originalText: String) {
        guard !dates.contains(where: { abs($0.timeIntervalSince(date)) < 60 }) else {
            appendDateString(originalText)
            return
        }

        dates.append(date)
        dateStrings.appendUnique(originalText)
        sortDatesAndStrings()
    }

    mutating func appendDateString(_ value: String) {
        let trimmedValue = value.trimmed
        guard !trimmedValue.isEmpty else {
            return
        }

        dateStrings.appendUnique(trimmedValue)
    }

    mutating func appendPhoneNumber(_ value: String) {
        let normalizedValue = value.trimmed
        guard !normalizedValue.isEmpty,
              !phoneNumbers.contains(where: { $0.phoneDedupKey == normalizedValue.phoneDedupKey }) else {
            return
        }

        phoneNumbers.append(normalizedValue)
    }

    mutating func appendURL(_ value: String) {
        let normalizedValue = value.trimmed
        guard !normalizedValue.isEmpty,
              !urls.contains(where: { $0.urlDedupKey == normalizedValue.urlDedupKey }) else {
            return
        }

        urls.append(normalizedValue)
    }

    mutating func appendAddress(_ value: String) {
        let normalizedValue = value.trimmed
        guard !normalizedValue.isEmpty,
              !addresses.contains(where: { $0.caseInsensitiveCompare(normalizedValue) == .orderedSame }) else {
            return
        }

        addresses.append(normalizedValue)
    }

    mutating func sortDatesAndStrings() {
        let pairs = dates.enumerated()
            .map { index, date in
                (date: date, text: dateStrings[safe: index] ?? "")
            }
            .sorted { $0.date < $1.date }

        dates = pairs.map(\.date)
        dateStrings = pairs.map(\.text).filter { !$0.isEmpty }
    }
}

private extension String {
    var phoneDedupKey: String {
        filter { $0.isNumber || $0 == "+" }
    }

    var urlDedupKey: String {
        lowercased()
            .replacingOccurrences(of: "https://", with: "")
            .replacingOccurrences(of: "http://", with: "")
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }
}

private extension Array where Element: Equatable {
    mutating func appendUnique(_ value: Element) {
        if !contains(value) {
            append(value)
        }
    }
}

private extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
