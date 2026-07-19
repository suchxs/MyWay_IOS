// WaypointsActivity.kt → SwiftUI. Individual saved waypoints (not grouped): name, note, which
// collection they're in, with edit (name/note/collection) + delete, and tap-to-focus on the map.
import SwiftUI
import CoreLocation

struct WaypointsView: View {
    @EnvironmentObject var state: AppState
    var onFocus: (CLLocationCoordinate2D) -> Void
    @State private var editKey: String?
    @State private var confirmDeleteAll = false

    var body: some View {
        Group {
            if state.places.isEmpty {
                ContentUnavailableViewCompat(text: "No waypoints saved yet.\nUse Pin mode or long-press the map to save a location.")
            } else {
                List {
                    ForEach(state.places) { p in
                        Button { onFocus(p.coordinate) } label: { row(p) }
                            .tint(.primary)
                            .swipeActions {
                                Button(role: .destructive) { state.removeLocation(p) } label: { Label("Delete", systemImage: "trash") }
                                Button { editKey = p.key } label: { Label("Edit", systemImage: "pencil") }.tint(Brand.teal)
                            }
                    }
                }
            }
        }
        .navigationTitle("Saved Waypoints")
        .toolbar {
            if !state.places.isEmpty {
                ToolbarItem(placement: .primaryAction) {
                    Button(role: .destructive) { confirmDeleteAll = true } label: {
                        Image(systemName: "trash").foregroundColor(Color(hex: 0xEF4444))
                    }
                }
            }
        }
        .alert("Delete all waypoints?", isPresented: $confirmDeleteAll) {
            Button("Delete All", role: .destructive) { state.clearMyPlaces() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently removes every saved waypoint and note, on all your devices. Collections are kept. This can't be undone.")
        }
        .sheet(item: Binding(get: { editKey.map { IdString($0) } }, set: { editKey = $0?.value })) { id in
            if let place = state.places.first(where: { $0.key == id.value }) { EditWaypointSheet(place: place) }
        }
    }

    private func row(_ p: SavedPlace) -> some View {
        let collection = state.collections.first { $0.locationKeys.contains(p.key) }
        return HStack {
            Text("📍").font(.title3).frame(width: 40, height: 40)
                .background(Brand.teal.opacity(0.15)).clipShape(RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 2) {
                Text(p.name.isEmpty ? "Unnamed location" : p.name).bold()
                if !p.note.isEmpty { Text(p.note).font(.caption).foregroundColor(.secondary).lineLimit(1) }
                if let c = collection { Text("\(c.icon) \(c.name)").font(.caption2).bold().foregroundColor(Brand.teal) }
            }
            Spacer()
        }
    }
}

private struct EditWaypointSheet: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss
    let place: SavedPlace
    @State private var name = ""
    @State private var note = ""
    @State private var collectionId: String?

    var body: some View {
        NavigationStack {
            Form {
                Section { TextField("Name", text: $name); TextField("Note", text: $note, axis: .vertical).lineLimit(2...4) }
                Section("Collection") {
                    Picker("Collection", selection: $collectionId) {
                        Text("None").tag(String?.none)
                        ForEach(state.collections) { c in Text("\(c.icon) \(c.name)").tag(String?.some(c.id)) }
                    }
                }
            }
            .navigationTitle("Edit Waypoint")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        state.saveName(place.key, name)
                        state.saveNote(place.key, note)
                        state.setPinCollection(place.key, target: state.collections.first { $0.id == collectionId })
                        dismiss()
                    }
                }
            }
            .onAppear {
                name = place.name; note = place.note
                collectionId = state.collections.first { $0.locationKeys.contains(place.key) }?.id
            }
        }
    }
}

// Small helpers.
struct IdString: Identifiable { let value: String; var id: String { value }; init(_ v: String) { value = v } }

struct ContentUnavailableViewCompat: View {
    let text: String
    var body: some View {
        VStack { Text(text).multilineTextAlignment(.center).foregroundColor(.secondary) }
            .frame(maxWidth: .infinity, maxHeight: .infinity).padding(32)
    }
}
