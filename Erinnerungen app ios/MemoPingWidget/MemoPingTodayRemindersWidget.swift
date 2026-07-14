import SwiftUI
import WidgetKit

struct MemoPingTodayReminderEntry: TimelineEntry {
    let date: Date
    let snapshot: MemoWidgetSnapshot
}

struct MemoPingTodayReminderProvider: TimelineProvider {
    func placeholder(in context: Context) -> MemoPingTodayReminderEntry {
        MemoPingTodayReminderEntry(
            date: Date(),
            snapshot: MemoWidgetSnapshot(
                generatedAt: Date(),
                reminders: [
                    MemoWidgetReminderSnapshot(
                        id: UUID().uuidString,
                        title: "Arzttermin",
                        dueDate: Date().addingTimeInterval(3_600),
                        isCompleted: false
                    )
                ]
            )
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (MemoPingTodayReminderEntry) -> Void) {
        completion(makeEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<MemoPingTodayReminderEntry>) -> Void) {
        let entry = makeEntry()
        let now = Date()
        let calendar = Calendar.current

        // Spätestens um Mitternacht aktualisieren, damit gestrige Erinnerungen verschwinden.
        let in15Minutes = now.addingTimeInterval(15 * 60)
        let startOfTomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? in15Minutes
        let nextUpdate = min(in15Minutes, startOfTomorrow)

        completion(Timeline(entries: [entry], policy: .after(nextUpdate)))
    }

    /// Filtert den gespeicherten Snapshot beim Rendern erneut auf "heute und offen",
    /// damit ein veralteter Snapshot keine gestrigen Erinnerungen anzeigt.
    private func makeEntry() -> MemoPingTodayReminderEntry {
        let snapshot = MemoWidgetSnapshotStore.load()
        let calendar = Calendar.current

        let todaysReminders = snapshot.reminders.filter { reminder in
            !reminder.isCompleted && calendar.isDateInToday(reminder.dueDate)
        }

        return MemoPingTodayReminderEntry(
            date: Date(),
            snapshot: MemoWidgetSnapshot(generatedAt: snapshot.generatedAt, reminders: todaysReminders)
        )
    }
}

struct MemoPingTodayReminderWidgetView: View {
    let entry: MemoPingTodayReminderEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Heute", systemImage: "bell")
                    .font(.headline)
                Spacer()
                if !entry.snapshot.reminders.isEmpty {
                    Text("\(entry.snapshot.reminders.count) offen")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            if entry.snapshot.reminders.isEmpty {
                Spacer()
                Text("Keine offenen Erinnerungen")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(entry.snapshot.reminders.prefix(4)) { reminder in
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(reminder.dueDate.formatted(date: .omitted, time: .shortened))
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.secondary)
                                .frame(width: 44, alignment: .leading)

                            Text(reminder.title)
                                .font(.caption)
                                .lineLimit(1)
                        }
                    }
                }

                Spacer(minLength: 0)
            }
        }
        .containerBackground(.background, for: .widget)
    }
}

struct MemoPingTodayRemindersWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: MemoPingWidgetConstants.todayReminderKind,
            provider: MemoPingTodayReminderProvider()
        ) { entry in
            MemoPingTodayReminderWidgetView(entry: entry)
        }
        .configurationDisplayName("RemindlyAi Erinnerungen")
        .description("Zeigt deine offenen Erinnerungen für heute.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
