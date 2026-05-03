// Build binary (optional, faster to invoke):
//   swiftc -parse-as-library -O -o list-reminders list-reminders.swift
// Run interpreted:
//   xcrun swift list-reminders.swift [--overdue [--include-notes]] | --set-due <id> <unixSeconds> [--dry-run]]
import Darwin
import EventKit
import Foundation

@main
enum ListReminders {
  struct ReminderOutput: Codable {
    let id: String
    let title: String
    let isCompleted: Bool
    let dueDate: String?
    let calendarTitle: String
    let notes: String?
  }

  private static let iso8601: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime]
    return f
  }()

  private static func isoString(from date: Date?) -> String? {
    guard let date else { return nil }
    return iso8601.string(from: date)
  }

  private static func fetchIncompleteReminders(store: EKEventStore) async -> [EKReminder] {
    let predicate = store.predicateForIncompleteReminders(
      withDueDateStarting: nil,
      ending: nil,
      calendars: nil
    )
    return await withCheckedContinuation { continuation in
      store.fetchReminders(matching: predicate) { reminders in
        continuation.resume(returning: reminders ?? [])
      }
    }
  }

  private static func requestAccess(store: EKEventStore) async -> Bool {
    do {
      return try await store.requestFullAccessToReminders()
    } catch {
      fputs(
        "Error requesting Reminders access: \(error.localizedDescription)\n",
        stderr
      )
      return false
    }
  }

  /// Incomplete, has a due date, due strictly before local start of today.
  private static func overdueBeforeToday(from reminders: [EKReminder]) -> [EKReminder] {
    let cal = Calendar.current
    let todayStart = cal.startOfDay(for: Date())
    let filtered = reminders.filter { r in
      guard !r.isCompleted, let due = r.dueDateComponents?.date else { return false }
      return due < todayStart
    }
    return filtered.sorted {
      let a = $0.dueDateComponents?.date ?? .distantFuture
      let b = $1.dueDateComponents?.date ?? .distantFuture
      return a < b
    }
  }

  private static func encodeOutputs(_ output: [ReminderOutput]) throws -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let data = try encoder.encode(output)
    guard let json = String(data: data, encoding: .utf8) else {
      throw NSError(domain: "ListReminders", code: 1, userInfo: [
        NSLocalizedDescriptionKey: "UTF-8 decode failed",
      ])
    }
    return json
  }

  private static let overdueNotesMaxChars = 240

  private static func truncatedNotes(_ raw: String?, maxChars: Int) -> String? {
    guard let raw, !raw.isEmpty else { return nil }
    if raw.count <= maxChars { return raw }
    return String(raw.prefix(maxChars))
  }

  private static func reminderOutput(
    _ reminder: EKReminder,
    includeNotes: Bool,
    truncateNotesTo maxChars: Int? = nil
  ) -> ReminderOutput {
    let rawNotes = includeNotes ? reminder.notes : nil
    let notes: String?
    if let rawNotes, let maxChars = maxChars {
      notes = Self.truncatedNotes(rawNotes, maxChars: maxChars)
    } else {
      notes = rawNotes
    }
    return ReminderOutput(
      id: reminder.calendarItemIdentifier,
      title: reminder.title ?? "(Untitled)",
      isCompleted: reminder.isCompleted,
      dueDate: Self.isoString(from: reminder.dueDateComponents?.date),
      calendarTitle: reminder.calendar.title,
      notes: notes
    )
  }

  /// `unixSeconds`: wall-clock instant (`Date.timeIntervalSince1970`), same as JS `Date.getTime()/1000`.
  private static func setDueById(
    store: EKEventStore,
    id: String,
    unixSeconds: TimeInterval,
    dryRun: Bool
  ) throws {
    guard let item = store.calendarItem(withIdentifier: id) as? EKReminder else {
      throw NSError(domain: "ListReminders", code: 2, userInfo: [
        NSLocalizedDescriptionKey: "No reminder with id \(id)",
      ])
    }
    let dueDate = Date(timeIntervalSince1970: unixSeconds)
    let cal = Calendar.current
    item.dueDateComponents = cal.dateComponents(
      [.year, .month, .day, .hour, .minute, .second],
      from: dueDate
    )
    if dryRun {
      fputs(
        "[DRY_RUN] Would set due for \"\(item.title ?? "")\" to \(dueDate)\n",
        stderr
      )
      return
    }
    try store.save(item, commit: true)
    fputs("Saved due date for \"\(item.title ?? "")\".\n", stderr)
  }

  static func main() async {
    let argv = Array(CommandLine.arguments.dropFirst())

    if let i = argv.firstIndex(of: "--set-due") {
      guard argv.count >= i + 3 else {
        fputs("Usage: ... --set-due <calendarItemIdentifier> <unixSeconds> [--dry-run]\n", stderr)
        exit(1)
      }
      let id = argv[i + 1]
      guard let secs = TimeInterval(argv[i + 2]) else {
        fputs("Invalid unixSeconds: \(argv[i + 2])\n", stderr)
        exit(1)
      }
      let dryRun = argv.contains("--dry-run")
      let store = EKEventStore()
      guard await requestAccess(store: store) else {
        fputs("Reminders access was not granted.\n", stderr)
        exit(1)
      }
      do {
        try setDueById(store: store, id: id, unixSeconds: secs, dryRun: dryRun)
      } catch {
        fputs("Save failed: \(error.localizedDescription)\n", stderr)
        exit(1)
      }
      return
    }

    let overdueOnly = argv.contains("--overdue")
    let includeNotesForOverdue = argv.contains("--include-notes")
    let store = EKEventStore()

    guard await requestAccess(store: store) else {
      fputs("Reminders access was not granted.\n", stderr)
      exit(1)
    }

    fputs("Fetching incomplete reminders...\n", stderr)
    let reminders = await fetchIncompleteReminders(store: store)

    let selected: [EKReminder]
    if overdueOnly {
      selected = overdueBeforeToday(from: reminders)
      fputs(
        "Filtered to \(selected.count) overdue (due before start of today), of \(reminders.count) incomplete.\n",
        stderr
      )
    } else {
      selected = reminders
      fputs("Found \(reminders.count) incomplete reminders.\n", stderr)
    }

    let includeNotes = !overdueOnly || includeNotesForOverdue
    let noteTruncate = overdueOnly && includeNotesForOverdue ? Self.overdueNotesMaxChars : nil
    let output = selected.map { reminderOutput($0, includeNotes: includeNotes, truncateNotesTo: noteTruncate) }

    if !overdueOnly {
      for (index, reminder) in selected.enumerated() {
        fputs(
          "Processing \(index + 1)/\(selected.count): \(reminder.title ?? "(Untitled)")\n",
          stderr
        )
      }
    }

    do {
      print(try encodeOutputs(output))
    } catch {
      fputs("Failed encoding JSON: \(error.localizedDescription)\n", stderr)
      exit(1)
    }
  }
}
