// Schedule (or immediately start) a trip — mirrors Android's ScheduleTripDialog. Time defaults to now;
// picking a future date/time schedules it (a past time is rejected). Scheduling creates the shared plan
// with the given name, then hands off to the activity queue (PlanView) to fill it in.
import SwiftUI

/// Android's stamp(): same-day → "3:30 PM", otherwise "Aug 4, 3:30 PM".
func tripStamp(_ date: Date) -> String {
    let sameDay = Calendar.current.isDate(date, inSameDayAs: Date())
    return date.formatted(sameDay ? .dateTime.hour().minute()
                                  : .dateTime.month().day().hour().minute())
}

struct ScheduleTripSheet: View {
    @Environment(\.dismiss) private var dismiss
    let group: TravelGroup
    let myUid: String
    let myTag: String
    var onStartNow: () -> Void          // start immediately (start session + join)
    var onScheduled: () -> Void         // scheduled → open the activity queue

    @State private var name = ""
    @State private var startAt = Date()

    // A minute of slack so "now" isn't a moving target while the sheet is open.
    private var isFuture: Bool { startAt > Date().addingTimeInterval(60) }
    private var inPast: Bool { startAt < Date().addingTimeInterval(-60) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Trip name", text: $name)
                    DatePicker("Starts", selection: $startAt, in: Date()..., displayedComponents: [.date, .hourAndMinute])
                    Text(isFuture ? "Scheduled for \(tripStamp(startAt)) — the group is notified a day and 15 min before."
                                  : "Starts now. Pick a later time to schedule instead.")
                        .font(.caption).foregroundColor(.secondary)
                }
            }
            .navigationTitle("Start a trip")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isFuture ? "Schedule" : "Start now") { submit() }.bold().disabled(inPast)
                }
            }
        }
    }

    private func submit() {
        if isFuture {
            let planName = name.trimmed.isEmpty ? "Trip plan" : name.trimmed
            Trip.scheduleSession(group.id, startAt: startAt) { err in
                if err == nil { Trip.createPlan(group.id, name: planName, actorUid: myUid, actorTag: myTag) { _ in } }
            }
            dismiss(); onScheduled()
        } else {
            dismiss(); onStartNow()
        }
    }
}
