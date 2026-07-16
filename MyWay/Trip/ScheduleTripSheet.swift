// Booking sheet shown when you tap "Start Trip". Defaults to now (→ start immediately); pick a future
// time to schedule instead. Name the trip and queue the planned stops; the queue becomes the trip plan.
import SwiftUI
import CoreLocation

struct ScheduleTripSheet: View {
    @Environment(\.dismiss) private var dismiss
    let group: TravelGroup
    let myUid: String
    let myTag: String

    @State private var name = ""
    @State private var startAt = Date()
    @State private var stops: [ScheduledStop] = []
    @State private var showSearch = false
    @State private var error: String?

    // A minute of slack so "now" isn't a moving target while the sheet is open.
    private var isFuture: Bool { startAt > Date().addingTimeInterval(60) }

    var body: some View {
        NavigationStack {
            Form {
                Section("Trip") {
                    TextField("Trip name", text: $name)
                    DatePicker("Starts", selection: $startAt, in: Date()..., displayedComponents: [.date, .hourAndMinute])
                }
                Section("Planned stops") {
                    ForEach(stops, id: \.id) { s in Text(s.name.isEmpty ? "Stop" : s.name) }
                        .onDelete { stops.remove(atOffsets: $0) }
                    Button { showSearch = true } label: { Label("Add a place", systemImage: "plus.circle") }.tint(Brand.teal)
                    if stops.isEmpty { Text("Optional — add the places you plan to visit.").font(.caption).foregroundColor(.secondary) }
                }
                if let error { Section { Text(error).foregroundColor(Color(hex: 0xEF4444)) } }
            }
            .navigationTitle("Start a trip")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isFuture ? "Schedule" : "Start now") { submit() }.bold()
                        .disabled(isFuture && name.trimmed.isEmpty)
                }
            }
            .sheet(isPresented: $showSearch) {
                PlaceSearchView { _, placeName, coord in
                    stops.append(ScheduledStop(id: String(UUID().uuidString.prefix(10)), name: placeName,
                                               lat: coord.latitude, lng: coord.longitude))
                }
            }
        }
    }

    private func submit() {
        if isFuture {
            guard startAt > Date() else { error = "Pick a time in the future."; return }
            let sched = ScheduledTrip(name: name.trimmed.isEmpty ? group.name : name.trimmed,
                                      startAt: startAt, by: myUid, byTag: myTag, items: stops)
            Trip.scheduleTrip(group.id, sched: sched)
            Groups.postSystem(group.id, text: "@\(myTag) scheduled “\(sched.name)” for \(Self.when(startAt))")
        } else {
            Trip.startScheduledNow(group.id, name: name.trimmed, stops: stops, actorUid: myUid, actorTag: myTag)
            TripManager.shared.joinTrip(gid: group.id, groupName: group.name, tripActive: true)
        }
        dismiss()
    }

    static func when(_ d: Date) -> String {
        d.formatted(.dateTime.weekday(.abbreviated).month().day().hour().minute())
    }
}
