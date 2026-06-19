import SwiftUI

struct MemoCardView: View {
    let item: MemoItem
    var category: MemoCategoryItem? = nil
    var onToggleCompleted: (() -> Void)?
    var onDelete: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                Button {
                    onToggleCompleted?()
                } label: {
                    Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 30, weight: .semibold))
                        .foregroundStyle(item.isCompleted ? Color.green : cardTint)
                        .frame(width: 34, height: 34)
                }
                .buttonStyle(.borderless)
                .disabled(onToggleCompleted == nil)
                .accessibilityLabel(item.isCompleted ? "Als offen markieren" : "Als erledigt markieren")

                VStack(alignment: .leading, spacing: 4) {
                    Text(item.title)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(item.isCompleted ? .secondary : .white)
                        .strikethrough(item.isCompleted)
                        .lineLimit(2)

                    Text(item.previewText)
                        .font(.body)
                        .foregroundStyle(.white.opacity(0.62))
                        .lineLimit(3)
                }

                Spacer(minLength: 8)

                if let onDelete {
                    Button(role: .destructive) {
                        onDelete()
                    } label: {
                        Image(systemName: "trash")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(Color(red: 1.0, green: 0.28, blue: 0.42))
                            .frame(width: 34, height: 34)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Memo löschen")
                }
            }

            metadataRow
        }
        .padding(18)
        .background(cardBackground, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(cardTint.opacity(0.35), lineWidth: 1)
        }
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(cardTint)
                .frame(width: 5)
                .padding(.vertical, 18)
        }
        .opacity(item.isCompleted ? 0.72 : 1)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private var iconName: String {
        if item.hasReminder {
            return "bell.circle"
        }
        if !item.imageFileNames.isEmpty {
            return "photo.circle"
        }
        return "note.text"
    }

    private var cardTint: Color {
        if let category {
            return category.tint
        }

        if item.priority != .normal {
            return item.priority.tint
        }

        if item.hasReminder {
            return Color(red: 0.52, green: 0.30, blue: 1.0)
        }

        return Color(red: 1.0, green: 0.25, blue: 0.56)
    }

    private var cardBackground: LinearGradient {
        LinearGradient(
            colors: [
                cardTint.opacity(0.22),
                Color(red: 0.10, green: 0.07, blue: 0.16).opacity(0.96),
                Color(red: 0.06, green: 0.05, blue: 0.09).opacity(0.98)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var metadataRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                if let category {
                    memoBadge(category.displayName, systemImage: category.systemImage, tint: category.tint)
                }

                memoBadge(item.priority.displayName, systemImage: item.priority.systemImage, tint: item.priority.tint)

                if item.hasReminder, let reminderDate = item.reminderDate {
                    memoBadge(reminderDate.formatted(date: .abbreviated, time: .shortened), systemImage: "bell", tint: .secondary)

                    if item.reminderRepeatRule.isRepeating {
                        memoBadge(item.reminderRepeatRule.displayName, systemImage: item.reminderRepeatRule.systemImage, tint: .secondary)
                    }

                    if item.reminderLeadTime.hasLeadNotification {
                        memoBadge(item.reminderLeadTime.shortDisplayName, systemImage: item.reminderLeadTime.systemImage, tint: .secondary)
                    }
                }

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
            .padding(.vertical, 1)
        }
        .accessibilityLabel("Details zur Erinnerung")
    }

    private func memoBadge(_ title: String, systemImage: String, tint: Color) -> some View {
        Label(title, systemImage: systemImage)
            .labelStyle(.titleAndIcon)
            .font(.caption.weight(.medium))
            .foregroundStyle(tint)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(tint.opacity(0.12), in: Capsule())
    }

    private func iconBadge(_ systemImage: String, label: String) -> some View {
        Image(systemName: systemImage)
            .font(.caption.weight(.semibold))
            .foregroundStyle(Color.white.opacity(0.7))
            .frame(width: 26, height: 26)
            .background(Color.white.opacity(0.10), in: Circle())
            .accessibilityLabel(label)
    }
}
