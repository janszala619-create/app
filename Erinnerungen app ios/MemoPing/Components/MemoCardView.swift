import SwiftUI

struct MemoCardView: View {
    let item: MemoItem
    var category: MemoCategoryItem?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // MARK: - Titelzeile
            HStack(alignment: .top, spacing: 12) {
                // Status-Icon
                statusIcon
                    .frame(width: 28, height: 28)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 3) {
                    // Titel
                    Text(item.title)
                        .font(.headline)
                        .foregroundStyle(item.isCompleted ? .secondary : .primary)
                        .strikethrough(item.isCompleted)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)

                    // Fix C: Vorschautext nur anzeigen wenn er sich vom Titel unterscheidet
                    // und nicht leer ist
                    if shouldShowPreviewText {
                        Text(item.previewText)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Spacer(minLength: 4)

                // Bild-Indikator
                if !item.imageFileNames.isEmpty {
                    Image(systemName: "photo")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Enthält \(item.imageFileNames.count) Bild(er)")
                }
            }

            // MARK: - Badge-Zeile
            badgeRow
        }
        .padding(14)
        .background(
            Color(.secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06))
        }
        .opacity(item.isCompleted ? 0.7 : 1)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    // MARK: - Fix C: Vorschau nur wenn anders als Titel

    /// Zeigt den Vorschautext nur an, wenn er sich inhaltlich vom Titel unterscheidet.
    /// Verhindert doppelte Anzeige wenn der Titel aus dem Bodytext generiert wurde.
    private var shouldShowPreviewText: Bool {
        let preview = item.previewText.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = item.title.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !preview.isEmpty else { return false }

        // Wenn der Titel mit dem Anfang des Vorschautexts übereinstimmt → nicht nochmal zeigen
        // (Titel wird aus den ersten 6 Wörtern des Bodytexts generiert)
        let previewStart = preview
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .prefix(6)
            .joined(separator: " ")

        return !title.hasPrefix(previewStart.prefix(min(previewStart.count, title.count)))
            && title.lowercased() != preview.lowercased().prefix(title.count).description
    }

    // MARK: - Status Icon

    @ViewBuilder
    private var statusIcon: some View {
        if item.isCompleted {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.title3.weight(.semibold))
        } else if item.hasReminder {
            Image(systemName: "bell.circle.fill")
                .foregroundStyle(item.priority.tint)
                .font(.title3.weight(.semibold))
        } else if !item.imageFileNames.isEmpty {
            Image(systemName: "photo.circle.fill")
                .foregroundStyle(item.priority.tint)
                .font(.title3.weight(.semibold))
        } else {
            Image(systemName: "note.text")
                .foregroundStyle(item.priority.tint)
                .font(.title3.weight(.semibold))
        }
    }

    // MARK: - Badge Zeile

    private var badgeRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                // Kategorie
                if let category {
                    memoBadge(category.displayName, systemImage: category.systemImage, tint: category.tint)
                }

                // Priorität (nur wenn nicht normal — Normal ist der Default und braucht keinen Badge)
                if item.priority != .normal {
                    memoBadge(item.priority.displayName, systemImage: item.priority.systemImage, tint: item.priority.tint)
                }

                // Erinnerungsdatum
                if item.hasReminder, let reminderDate = item.reminderDate {
                    memoBadge(
                        reminderDate.germanFormatted(date: .abbreviated, time: .shortened),
                        systemImage: "bell",
                        tint: .secondary
                    )
                }

                // Erkannte Daten — kompakte Icons
                if !item.detectedPhoneNumbers.isEmpty {
                    iconBadge("phone", label: "Telefonnummer erkannt")
                }
                if !item.detectedURLs.isEmpty {
                    iconBadge("link", label: "Link erkannt")
                }
                if !item.detectedDateStrings.isEmpty {
                    iconBadge("calendar", label: "Datum erkannt")
                }
            }
        }
    }

    // MARK: - Badge Komponenten

    private func memoBadge(_ title: String, systemImage: String, tint: Color) -> some View {
        Label(title, systemImage: systemImage)
            .labelStyle(.titleAndIcon)
            .font(.caption.weight(.medium))
            .foregroundStyle(tint)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(tint.opacity(0.12), in: Capsule())
    }

    private func iconBadge(_ systemImage: String, label: String) -> some View {
        Image(systemName: systemImage)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .frame(width: 26, height: 26)
            .background(Color(.tertiarySystemGroupedBackground), in: Circle())
            .accessibilityLabel(label)
    }
}
