// PlaceSheets.kt (marker detail) → SwiftUI. Rename, note, assign one collection, share to a group, delete.
import SwiftUI
import CoreLocation

struct PlaceSheet: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss
    let place: SavedPlace
    let myUid: String
    let myTag: String
    var onDirections: (CLLocationCoordinate2D, String) -> Void = { _, _ in }
    var onViewLandmark: (SavedPlace) -> Void = { _ in }

    @State private var name = ""
    @State private var note = ""
    @State private var showShare = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name this place", text: $name)
                    TextField("Note", text: $note, axis: .vertical).lineLimit(2...5)
                }
                Section("Collection") {
                    Picker("Collection", selection: collectionBinding) {
                        Text("None").tag(String?.none)
                        ForEach(state.collections) { c in
                            Text("\(c.icon) \(c.name)").tag(String?.some(c.id))
                        }
                    }
                }
                Section {
                    Button { onDirections(place.coordinate, name.isEmpty ? "Saved pin" : name); dismiss() } label: {
                        Label("Directions", systemImage: "arrow.triangle.turn.up.right.diamond.fill")
                    }
                    if place.isLandmark {
                        Button { onViewLandmark(place); dismiss() } label: { Label("View landmark details", systemImage: "building.2") }
                    }
                    Button { showShare = true } label: { Label("Share to a group", systemImage: "square.and.arrow.up") }
                    Button(role: .destructive) {
                        state.removeLocation(place); dismiss()
                    } label: { Label("Delete pin", systemImage: "trash") }
                }
            }
            .navigationTitle(place.isLandmark ? "Landmark" : "Saved pin")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { persist(); dismiss() }
                }
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
            }
            .onAppear { name = place.name; note = place.note }
            .sheet(isPresented: $showShare) {
                GroupPickerSheet(myUid: myUid) { group in
                    Groups.sharePin(group.id, fromUid: myUid, fromTag: myTag,
                                    lat: place.lat, lng: place.lng, name: name, note: note, placeId: place.placeId)
                    showShare = false
                }
            }
        }
    }

    private var collectionBinding: Binding<String?> {
        Binding(
            get: { state.collections.first { $0.locationKeys.contains(place.key) }?.id },
            set: { id in state.setPinCollection(place.key, target: state.collections.first { $0.id == id }) }
        )
    }

    private func persist() {
        if name != place.name { state.saveName(place.key, name) }
        if note != place.note { state.saveNote(place.key, note) }
    }
}

/// One-shot picker: choose a group to share into (used by PlaceSheet + the share button).
struct GroupPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    let myUid: String
    let onPick: (TravelGroup) -> Void
    @State private var groups: [TravelGroup] = []

    var body: some View {
        NavigationStack {
            List(groups) { g in
                Button { onPick(g); dismiss() } label: {
                    HStack { AvatarCircle(photoBase64: g.photo, tag: g.name, size: 32); Text(g.name) }
                }
            }
            .navigationTitle("Share to group")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .onAppear { Groups.fetchMyGroups(myUid) { groups = $0 } }
        }
    }
}
