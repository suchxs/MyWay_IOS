// Trip roster (MainActivity's trip roster sheet): who's live, drop a shared pin, leave/end the trip.
import SwiftUI
import CoreLocation

struct TripRosterView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var trip: TripManager
    let myUid: String
    var myTag: String = ""
    var onFocusMember: (CLLocationCoordinate2D) -> Void

    @State private var showDropPin = false
    @State private var showPlan = false
    @State private var pinName = ""
    @State private var pinNote = ""

    var body: some View {
        NavigationStack {
            List {
                Section("Sharing now (\(trip.members.count))") {
                    ForEach(trip.members) { m in
                        Button {
                            if let lat = m.lat, let lng = m.lng {
                                onFocusMember(CLLocationCoordinate2D(latitude: lat, longitude: lng)); dismiss()
                            }
                        } label: {
                            HStack {
                                AvatarCircle(photoBase64: m.photo, tag: m.tag, size: 36)
                                Text("@\(m.tag)").bold() + Text(m.uid == myUid ? " (you)" : "").foregroundColor(.secondary)
                                Spacer()
                                if m.lat != nil { Image(systemName: "location.fill").foregroundColor(Brand.teal).font(.caption) }
                            }
                        }.tint(.primary)
                    }
                }
                if let dest = trip.dest {
                    Section("Destination") {
                        Label(dest.name.isEmpty ? "Shared destination" : dest.name, systemImage: "flag.checkered")
                        Text("set by @\(dest.byTag)").font(.caption).foregroundColor(.secondary)
                    }
                }
                Section {
                    Button { showPlan = true } label: { Label("Trip plan", systemImage: "list.bullet.clipboard") }
                    Button { showDropPin = true } label: { Label("Drop a trip pin here", systemImage: "mappin.and.ellipse") }
                    Button(role: .destructive) { trip.leaveTrip(); dismiss() } label: { Label("Leave trip", systemImage: "rectangle.portrait.and.arrow.right") }
                    Button(role: .destructive) { trip.endTrip(); dismiss() } label: { Label("End trip for everyone", systemImage: "xmark.octagon") }
                }
            }
            .navigationTitle("Live trip")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
            .sheet(isPresented: $showPlan) {
                if let gid = trip.currentGid {
                    PlanView(gid: gid, actorUid: myUid, actorTag: myTag, tripPins: trip.pins)
                }
            }
            .alert("Drop a trip pin", isPresented: $showDropPin) {
                TextField("Name", text: $pinName)
                TextField("Note", text: $pinNote)
                Button("Drop") { trip.dropPin(name: pinName, note: pinNote); pinName = ""; pinNote = "" }
                Button("Cancel", role: .cancel) {}
            } message: { Text("Marks your current location for the group.") }
        }
    }
}
